//! Parsing of HTTP/1.x request heads.
//!
//! The method is kept as a raw token (rather than `std.http.Method`) so that
//! any syntactically valid method reaches the router and can be answered with
//! `405 Method Not Allowed` instead of being rejected as a protocol error.

const std = @import("std");
const mem = std.mem;

pub const Head = struct {
    method: []const u8,
    target: []const u8,
    content_length: ?u64 = null,
    chunked: bool = false,
    expect_continue: bool = false,

    /// Whether the request carries a message body that must be read or
    /// discarded.
    pub fn hasBody(head: Head) bool {
        return head.chunked or (head.content_length orelse 0) > 0;
    }

    /// The request path: the target without any query string.
    pub fn path(head: Head) []const u8 {
        return head.target[0 .. mem.findScalar(u8, head.target, '?') orelse head.target.len];
    }
};

pub const ParseError = error{
    /// The head violates HTTP/1.x syntax or framing rules.
    BadRequest,
    /// The client sent an `Expect` header other than `100-continue`.
    ExpectationFailed,
};

/// Parses a complete request head, as buffered by `std.http.Reader.receiveHead`.
/// The returned slices point into `bytes`.
pub fn parse(bytes: []const u8) ParseError!Head {
    var lines = mem.splitScalar(u8, bytes, '\n');

    const request_line = trimCr(lines.first());
    var parts = mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.BadRequest;
    const target = parts.next() orelse return error.BadRequest;
    const version = parts.next() orelse return error.BadRequest;
    if (parts.next() != null) return error.BadRequest;
    if (!isToken(method)) return error.BadRequest;
    if (target.len == 0 or !isVisible(target)) return error.BadRequest;
    if (!mem.eql(u8, version, "HTTP/1.1") and !mem.eql(u8, version, "HTTP/1.0")) return error.BadRequest;

    var head: Head = .{ .method = method, .target = target };
    var expectation_failed = false;

    while (lines.next()) |raw_line| {
        const line = trimCr(raw_line);
        if (line.len == 0) break;
        // Obsolete line folding is not accepted (RFC 9112 §5.2).
        if (line[0] == ' ' or line[0] == '\t') return error.BadRequest;

        const colon = mem.findScalar(u8, line, ':') orelse return error.BadRequest;
        const name = line[0..colon];
        const value = mem.trim(u8, line[colon + 1 ..], " \t");
        if (!isToken(name)) return error.BadRequest;

        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            if (head.content_length != null) return error.BadRequest;
            head.content_length = parseContentLength(value) orelse return error.BadRequest;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            // Only `chunked` is supported, and it must be the final coding.
            if (head.chunked) return error.BadRequest;
            var codings = mem.splitBackwardsScalar(u8, value, ',');
            const last = mem.trim(u8, codings.first(), " \t");
            if (!std.ascii.eqlIgnoreCase(last, "chunked") or codings.next() != null) return error.BadRequest;
            head.chunked = true;
        } else if (std.ascii.eqlIgnoreCase(name, "expect")) {
            if (std.ascii.eqlIgnoreCase(value, "100-continue")) {
                head.expect_continue = true;
            } else {
                expectation_failed = true;
            }
        }
    }

    // A message with both framings is a request smuggling vector (RFC 9112 §6.1).
    if (head.chunked and head.content_length != null) return error.BadRequest;
    if (expectation_failed) return error.ExpectationFailed;
    return head;
}

fn trimCr(line: []const u8) []const u8 {
    return if (mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

fn parseContentLength(value: []const u8) ?u64 {
    if (value.len == 0) return null;
    for (value) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseUnsigned(u64, value, 10) catch null;
}

/// RFC 9110 `token`: one or more `tchar`.
fn isToken(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        const ok = std.ascii.isAlphanumeric(c) or mem.findScalar(u8, "!#$%&'*+-.^_`|~", c) != null;
        if (!ok) return false;
    }
    return true;
}

fn isVisible(s: []const u8) bool {
    for (s) |c| if (c <= ' ' or c == 0x7f) return false;
    return true;
}

const testing = std.testing;

test "parse simple request" {
    const head = try parse("PUT /kv/a?x=1 HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\nConnection: close\r\n\r\n");
    try testing.expectEqualStrings("PUT", head.method);
    try testing.expectEqualStrings("/kv/a?x=1", head.target);
    try testing.expectEqualStrings("/kv/a", head.path());
    try testing.expectEqual(5, head.content_length.?);
    try testing.expect(head.hasBody());
    try testing.expect(!head.chunked);
}

test "parse custom method and chunked body" {
    const head = try parse("PURGE / HTTP/1.1\r\ntransfer-encoding: chunked\r\nexpect: 100-continue\r\n\r\n");
    try testing.expectEqualStrings("PURGE", head.method);
    try testing.expect(head.chunked);
    try testing.expect(head.expect_continue);
}

test "reject malformed heads" {
    try testing.expectError(error.BadRequest, parse("GET /\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse("GET / HTTP/2.0\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse("GET / HTTP/1.1\r\nContent-Length: 1x\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse("GET / HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse("GET / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse("GET / HTTP/1.1\r\nBad Header: x\r\n\r\n"));
    try testing.expectError(error.ExpectationFailed, parse("PUT / HTTP/1.1\r\nExpect: magic\r\n\r\n"));
}
