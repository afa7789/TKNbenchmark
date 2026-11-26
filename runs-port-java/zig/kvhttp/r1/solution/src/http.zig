//! Minimal HTTP/1.1 request-head parsing and response serialization.
//!
//! `std.http.Server` only accepts the methods in `std.http.Method`; this
//! server must answer arbitrary method tokens with `405`, so it parses the
//! request head itself.

const std = @import("std");
const Io = std.Io;
const Status = std.http.Status;

pub const Head = struct {
    method: []const u8,
    target: []const u8,
    content_length: ?u64 = null,
    expect_continue: bool = false,
    /// A `Transfer-Encoding` header was present. Only `Content-Length`
    /// framing is supported.
    has_transfer_encoding: bool = false,

    pub const ParseError = error{
        /// The request line or a header line is malformed.
        BadRequest,
        /// The HTTP version is not 1.x.
        VersionNotSupported,
        /// The `Expect` header has a value other than `100-continue`.
        ExpectationFailed,
    };

    /// Parses a complete request head (as returned by `receiveHead`).
    /// Slices in the result point into `bytes`.
    pub fn parse(bytes: []const u8) ParseError!Head {
        var lines = std.mem.splitScalar(u8, bytes, '\n');

        const request_line = trimCr(lines.first());
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return error.BadRequest;
        const target = parts.next() orelse return error.BadRequest;
        const version = parts.next() orelse return error.BadRequest;
        if (parts.next() != null) return error.BadRequest;
        if (method.len == 0 or !isToken(method)) return error.BadRequest;
        if (target.len == 0) return error.BadRequest;
        if (!std.mem.startsWith(u8, version, "HTTP/")) return error.BadRequest;
        if (!std.mem.startsWith(u8, version, "HTTP/1.")) return error.VersionNotSupported;

        var head: Head = .{ .method = method, .target = target };
        while (lines.next()) |raw_line| {
            const line = trimCr(raw_line);
            if (line.len == 0) break;
            if (line[0] == ' ' or line[0] == '\t') return error.BadRequest; // obsolete line folding

            const colon = std.mem.findScalar(u8, line, ':') orelse return error.BadRequest;
            const name = line[0..colon];
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (name.len == 0 or !isToken(name)) return error.BadRequest;

            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                const length = parseContentLength(value) orelse return error.BadRequest;
                if (head.content_length) |previous| {
                    if (previous != length) return error.BadRequest;
                }
                head.content_length = length;
            } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                head.has_transfer_encoding = true;
            } else if (std.ascii.eqlIgnoreCase(name, "expect")) {
                if (!std.ascii.eqlIgnoreCase(value, "100-continue")) return error.ExpectationFailed;
                head.expect_continue = true;
            }
        }
        return head;
    }

    fn trimCr(line: []const u8) []const u8 {
        return std.mem.trimEnd(u8, line, "\r");
    }

    fn parseContentLength(value: []const u8) ?u64 {
        if (value.len == 0) return null;
        for (value) |c| if (!std.ascii.isDigit(c)) return null;
        return std.fmt.parseInt(u64, value, 10) catch null;
    }

    /// RFC 9110 `token`.
    fn isToken(s: []const u8) bool {
        for (s) |c| switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9' => {},
            '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
            else => return false,
        };
        return true;
    }
};

pub const ReceiveHeadError = error{
    /// The head does not fit in the reader's buffer.
    HeadTooLarge,
} || Io.Reader.Error;

/// Reads from `r` until a complete request head has been buffered, then
/// consumes it and returns its bytes. The returned slice is valid until the
/// next read from `r`.
pub fn receiveHead(r: *Io.Reader) ReceiveHeadError![]const u8 {
    var parser: std.http.HeadParser = .{};
    var scanned: usize = 0;
    while (true) {
        const buffered = r.buffered();
        scanned += parser.feed(buffered[scanned..]);
        if (parser.state == .finished) {
            r.toss(scanned);
            return buffered[0..scanned];
        }
        if (buffered.len == r.buffer.len) return error.HeadTooLarge;
        try r.fillMore();
    }
}

pub const Response = struct {
    status: Status,
    content_type: ?[]const u8 = null,
    body: []const u8 = "",
};

/// Serializes a complete response. Every response closes the connection.
pub fn writeResponse(w: *Io.Writer, response: Response) Io.Writer.Error!void {
    try w.print("HTTP/1.1 {d} {s}\r\n", .{
        @intFromEnum(response.status), response.status.phrase() orelse "",
    });
    if (response.content_type) |content_type| {
        try w.print("Content-Type: {s}\r\n", .{content_type});
    }
    // A 204 response must not carry a body or a Content-Length (RFC 9110 §8.6).
    if (response.status != .no_content) {
        try w.print("Content-Length: {d}\r\n", .{response.body.len});
    }
    try w.writeAll("Connection: close\r\n\r\n");
    if (response.status != .no_content) try w.writeAll(response.body);
    try w.flush();
}

pub fn writeContinue(w: *Io.Writer) Io.Writer.Error!void {
    try w.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
    try w.flush();
}

const testing = std.testing;

test "parse request head" {
    const head = try Head.parse("PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\nConnection: close\r\n\r\n");
    try testing.expectEqualStrings("PUT", head.method);
    try testing.expectEqualStrings("/kv/a", head.target);
    try testing.expectEqual(5, head.content_length);
    try testing.expect(!head.has_transfer_encoding);
    try testing.expect(!head.expect_continue);
}

test "parse accepts arbitrary method tokens and bare LF" {
    const head = try Head.parse("FROB /health HTTP/1.0\nExpect: 100-continue\n\n");
    try testing.expectEqualStrings("FROB", head.method);
    try testing.expectEqual(null, head.content_length);
    try testing.expect(head.expect_continue);
}

test "parse rejects malformed heads" {
    try testing.expectError(error.BadRequest, Head.parse("GET /\r\n\r\n"));
    try testing.expectError(error.BadRequest, Head.parse("GET / HTTP/1.1 x\r\n\r\n"));
    try testing.expectError(error.BadRequest, Head.parse("GET / HTTP/1.1\r\nno-colon\r\n\r\n"));
    try testing.expectError(error.BadRequest, Head.parse("GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"));
    try testing.expectError(error.BadRequest, Head.parse("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"));
    try testing.expectError(error.VersionNotSupported, Head.parse("GET / HTTP/2.0\r\n\r\n"));
    try testing.expectError(error.ExpectationFailed, Head.parse("GET / HTTP/1.1\r\nExpect: nope\r\n\r\n"));
}

test "receiveHead leaves the body buffered" {
    var r: Io.Reader = .fixed("PUT /kv/a HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc");
    const bytes = try receiveHead(&r);
    try testing.expectEqualStrings("PUT /kv/a HTTP/1.1\r\nContent-Length: 3\r\n\r\n", bytes);
    try testing.expectEqualStrings("abc", r.buffered());
}

test "receiveHead reports truncated and oversized heads" {
    var buffer: [64]u8 = undefined;
    {
        var source: Io.Reader = .fixed("GET / HTTP/1.1\r\n");
        var limited = source.limited(.unlimited, &buffer);
        try testing.expectError(error.EndOfStream, receiveHead(&limited.interface));
    }
    {
        var source: Io.Reader = .fixed("GET / HTTP/1.1\r\nX-Long: " ++ "x" ** 64 ++ "\r\n\r\n");
        var limited = source.limited(.unlimited, &buffer);
        try testing.expectError(error.HeadTooLarge, receiveHead(&limited.interface));
    }
}

test "writeResponse" {
    var buf: [256]u8 = undefined;
    {
        var w: Io.Writer = .fixed(&buf);
        try writeResponse(&w, .{ .status = .ok, .content_type = "text/plain", .body = "ok" });
        try testing.expectEqualStrings(
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
            w.buffered(),
        );
    }
    {
        var w: Io.Writer = .fixed(&buf);
        try writeResponse(&w, .{ .status = .no_content });
        try testing.expectEqualStrings("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n", w.buffered());
    }
}
