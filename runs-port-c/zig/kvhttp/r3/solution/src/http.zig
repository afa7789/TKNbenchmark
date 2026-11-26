//! Minimal HTTP/1.1 request-head parsing and response formatting.

const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const Io = std.Io;

pub const Status = enum(u16) {
    @"continue" = 100,
    ok = 200,
    created = 201,
    no_content = 204,
    bad_request = 400,
    not_found = 404,
    method_not_allowed = 405,
    request_timeout = 408,
    content_too_large = 413,
    request_header_fields_too_large = 431,
    internal_server_error = 500,
    not_implemented = 501,
    service_unavailable = 503,
    http_version_not_supported = 505,

    pub fn phrase(status: Status) []const u8 {
        return switch (status) {
            .@"continue" => "Continue",
            .ok => "OK",
            .created => "Created",
            .no_content => "No Content",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .request_timeout => "Request Timeout",
            .content_too_large => "Content Too Large",
            .request_header_fields_too_large => "Request Header Fields Too Large",
            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .service_unavailable => "Service Unavailable",
            .http_version_not_supported => "HTTP Version Not Supported",
        };
    }
};

/// A parsed request head. Slices point into the buffer given to `parseHead`.
pub const Request = struct {
    method: []const u8,
    target: []const u8,
    content_length: usize = 0,
    expect_continue: bool = false,
};

/// Reasons a request head is rejected, each mapped to a response status.
pub const ParseError = error{
    BadRequest,
    NotImplemented,
    VersionNotSupported,
};

pub fn statusForError(err: ParseError) Status {
    return switch (err) {
        error.BadRequest => .bad_request,
        error.NotImplemented => .not_implemented,
        error.VersionNotSupported => .http_version_not_supported,
    };
}

pub const continue_line = "HTTP/1.1 100 Continue\r\n\r\n";

/// Returns the length of the request head (through the blank line) if `buf`
/// contains a complete head, otherwise null. Accepts both CRLF CRLF and bare
/// LF LF terminators.
pub fn headLength(buf: []const u8) ?usize {
    var i: usize = 0;
    while (mem.indexOfScalarPos(u8, buf, i, '\n')) |nl| : (i = nl + 1) {
        const rest = buf[nl + 1 ..];
        if (mem.startsWith(u8, rest, "\n")) return nl + 2;
        if (mem.startsWith(u8, rest, "\r\n")) return nl + 3;
    }
    return null;
}

/// Parses a complete request head as delimited by `headLength`.
pub fn parseHead(head: []const u8) ParseError!Request {
    // Tolerate leading empty lines (RFC 9112 section 2.2).
    const start = mem.indexOfNone(u8, head, "\r\n") orelse return error.BadRequest;
    if (head[head.len - 1] != '\n') return error.BadRequest;
    // Every piece is one LF-terminated line, with the LF removed.
    var lines = mem.splitScalar(u8, head[start .. head.len - 1], '\n');

    var req = try parseRequestLine(lines.first());

    var have_length = false;
    while (lines.next()) |raw| {
        const line = trim(raw);
        if (line.len == 0) break; // end of head
        if (raw[0] == ' ' or raw[0] == '\t') return error.BadRequest; // obsolete line folding

        const colon = mem.indexOfScalar(u8, line, ':') orelse return error.BadRequest;
        const name = line[0..colon];
        if (name.len == 0 or !isToken(name)) return error.BadRequest;
        const value = trim(line[colon + 1 ..]);

        if (ascii.eqlIgnoreCase(name, "Content-Length")) {
            const n = parseLength(value) orelse return error.BadRequest;
            if (have_length and n != req.content_length) return error.BadRequest;
            req.content_length = n;
            have_length = true;
        } else if (ascii.eqlIgnoreCase(name, "Transfer-Encoding")) {
            if (!ascii.eqlIgnoreCase(value, "identity")) return error.NotImplemented;
        } else if (ascii.eqlIgnoreCase(name, "Expect")) {
            if (ascii.eqlIgnoreCase(value, "100-continue")) req.expect_continue = true;
        }
    }
    return req;
}

fn parseRequestLine(line: []const u8) ParseError!Request {
    const sp1 = mem.indexOfScalar(u8, line, ' ') orelse return error.BadRequest;
    const sp2 = mem.indexOfScalarPos(u8, line, sp1 + 1, ' ') orelse return error.BadRequest;
    const method = line[0..sp1];
    const target = line[sp1 + 1 .. sp2];
    const version = trim(line[sp2 + 1 ..]);

    if (method.len == 0 or target.len == 0 or !isToken(method)) return error.BadRequest;
    if (version.len != 8 or !mem.startsWith(u8, version, "HTTP/") or
        !ascii.isDigit(version[5]) or version[6] != '.' or !ascii.isDigit(version[7]))
        return error.BadRequest;
    if (version[5] != '1') return error.VersionNotSupported;
    return .{ .method = method, .target = target };
}

fn trim(s: []const u8) []const u8 {
    const start = mem.trimStart(u8, s, " \t");
    return mem.trimEnd(u8, start, " \t\r");
}

fn isTokenChar(c: u8) bool {
    return ascii.isAlphanumeric(c) or mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", c) != null;
}

fn isToken(s: []const u8) bool {
    for (s) |c| if (!isTokenChar(c)) return false;
    return true;
}

/// Parses a Content-Length value: one or more digits, no sign, no overflow.
fn parseLength(v: []const u8) ?usize {
    if (v.len == 0) return null;
    for (v) |c| if (!ascii.isDigit(c)) return null;
    return std.fmt.parseUnsigned(usize, v, 10) catch null;
}

/// Writes a complete response with `Connection: close`. A 204 carries neither
/// a body nor a Content-Length.
pub fn writeResponse(
    w: *Io.Writer,
    status: Status,
    content_type: ?[]const u8,
    body: []const u8,
) Io.Writer.Error!void {
    try w.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase() });
    if (status == .no_content) {
        try w.writeAll("Connection: close\r\n\r\n");
        return;
    }
    if (content_type) |ct| try w.print("Content-Type: {s}\r\n", .{ct});
    try w.print("Content-Length: {d}\r\nConnection: close\r\n\r\n", .{body.len});
    try w.writeAll(body);
}

const testing = std.testing;

test headLength {
    try testing.expectEqual(null, headLength("GET / HTTP/1.1\r\nHost: x\r\n"));
    try testing.expectEqual(@as(?usize, 18), headLength("GET / HTTP/1.1\r\n\r\nbody"));
    try testing.expectEqual(@as(?usize, 16), headLength("GET / HTTP/1.1\n\nbody"));
}

test parseHead {
    const head = "PUT /kv/a HTTP/1.1\r\nContent-Length: 5\r\nexpect: 100-continue\r\n\r\n";
    const req = try parseHead(head);
    try testing.expectEqualStrings("PUT", req.method);
    try testing.expectEqualStrings("/kv/a", req.target);
    try testing.expectEqual(@as(usize, 5), req.content_length);
    try testing.expect(req.expect_continue);

    try testing.expectError(error.BadRequest, parseHead("GET /\r\n\r\n"));
    try testing.expectError(error.VersionNotSupported, parseHead("GET / HTTP/2.0\r\n\r\n"));
    try testing.expectError(error.NotImplemented, parseHead("GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseHead("GET / HTTP/1.1\r\n folded\r\n\r\n"));
    _ = try parseHead("\r\nGET / HTTP/1.1\r\nX: y\r\n\r\n");
}

test writeResponse {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeResponse(&w, .ok, "text/plain", "ok");
    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
        w.buffered(),
    );
    w = .fixed(&buf);
    try writeResponse(&w, .no_content, null, "");
    try testing.expectEqualStrings("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n", w.buffered());
}
