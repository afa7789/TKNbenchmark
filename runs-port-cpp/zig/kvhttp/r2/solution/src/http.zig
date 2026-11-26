//! Minimal HTTP/1.1 message types and request-head parsing.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    headers: []const Header,
    body: []const u8 = "",

    /// Case-insensitive header lookup; returns the first match.
    pub fn header(request: Request, name: []const u8) ?[]const u8 {
        for (request.headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }
};

pub const Response = struct {
    status: u16,
    headers: []const Header = &.{},
    body: []const u8 = "",

    pub fn empty(status: u16) Response {
        return .{ .status = status };
    }

    pub fn text(status: u16, body: []const u8) Response {
        return .{
            .status = status,
            .headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            .body = body,
        };
    }

    /// Writes the status line and headers, including `Content-Length` and
    /// `Connection: close`. The body is not included.
    pub fn writeHead(response: Response, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("HTTP/1.1 {d} {s}\r\n", .{ response.status, reasonPhrase(response.status) });
        for (response.headers) |h| {
            try w.print("{s}: {s}\r\n", .{ h.name, h.value });
        }
        // 204 responses must not carry a body; Content-Length is omitted there.
        if (response.status != 204) {
            try w.print("Content-Length: {d}\r\n", .{response.body.len});
        }
        try w.writeAll("Connection: close\r\n\r\n");
    }
};

pub fn reasonPhrase(status: u16) []const u8 {
    return switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        411 => "Length Required",
        413 => "Content Too Large",
        431 => "Request Header Fields Too Large",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        505 => "HTTP Version Not Supported",
        else => "Unknown",
    };
}

pub const ParseError = error{MalformedRequest} || Allocator.Error;

/// Parses a request head (request line and header fields, without the
/// terminating blank line). The returned request borrows from `head`; only the
/// header list is allocated with `gpa`.
pub fn parseHead(gpa: Allocator, head: []const u8) ParseError!Request {
    var lines = std.mem.splitSequence(u8, head, "\r\n");

    // Request line: METHOD SP request-target SP HTTP-version
    const request_line = lines.first();
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.first();
    const target = parts.next() orelse return error.MalformedRequest;
    const version = parts.rest();
    if (parts.next() == null) return error.MalformedRequest;
    if (!isToken(method) or target.len == 0 or !std.mem.startsWith(u8, version, "HTTP/1.")) {
        return error.MalformedRequest;
    }

    var headers: std.ArrayList(Header) = .empty;
    errdefer headers.deinit(gpa);
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.MalformedRequest;
        const name = line[0..colon];
        if (!isToken(name)) return error.MalformedRequest;
        try headers.append(gpa, .{
            .name = name,
            .value = std.mem.trim(u8, line[colon + 1 ..], " \t"),
        });
    }

    return .{
        .method = method,
        .target = target,
        .headers = try headers.toOwnedSlice(gpa),
    };
}

pub const IntError = error{ InvalidCharacter, Overflow };

/// Strictly parses an unsigned integer: one or more digits in `base`, with no
/// sign, prefix, separators or surrounding whitespace.
pub fn parseUnsigned(comptime T: type, text: []const u8, base: u8) IntError!T {
    if (text.len == 0) return error.InvalidCharacter;
    var result: T = 0;
    for (text) |c| {
        const digit = std.fmt.charToDigit(c, base) catch return error.InvalidCharacter;
        result = std.math.mul(T, result, base) catch return error.Overflow;
        result = std.math.add(T, result, digit) catch return error.Overflow;
    }
    return result;
}

fn isTokenChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", c) != null;
}

fn isToken(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!isTokenChar(c)) return false;
    }
    return true;
}

const testing = std.testing;

test parseHead {
    const request = try parseHead(testing.allocator, "PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length:  5 ");
    defer testing.allocator.free(request.headers);
    try testing.expectEqualStrings("PUT", request.method);
    try testing.expectEqualStrings("/kv/a", request.target);
    try testing.expectEqualStrings("5", request.header("Content-Length").?);
    try testing.expectEqual(null, request.header("Transfer-Encoding"));
}

test "parseHead rejects malformed heads" {
    const bad = [_][]const u8{
        "GET /health",
        "GET  HTTP/1.1",
        "G(T / HTTP/1.1",
        "GET / HTTP/2",
        "GET / HTTP/1.1\r\nno colon here",
        "GET / HTTP/1.1\r\nbad name: x",
    };
    for (bad) |head| {
        try testing.expectError(error.MalformedRequest, parseHead(testing.allocator, head));
    }
}

test parseUnsigned {
    try testing.expectEqual(@as(usize, 1234), try parseUnsigned(usize, "1234", 10));
    try testing.expectEqual(@as(usize, 0xff), try parseUnsigned(usize, "fF", 16));
    try testing.expectError(error.InvalidCharacter, parseUnsigned(usize, "", 10));
    try testing.expectError(error.InvalidCharacter, parseUnsigned(usize, "+1", 10));
    try testing.expectError(error.InvalidCharacter, parseUnsigned(usize, "1_0", 10));
    try testing.expectError(error.Overflow, parseUnsigned(u16, "65536", 10));
}

test "Response.writeHead" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try Response.text(200, "ok").writeHead(&w);
    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 2\r\nConnection: close\r\n\r\n",
        w.buffered(),
    );
}
