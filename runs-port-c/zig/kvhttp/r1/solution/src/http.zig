//! Minimal HTTP/1.1 request-head parsing and response serialization.
const std = @import("std");
const Io = std.Io;
const Status = std.http.Status;

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    content_length: ?usize = null,
};

/// The result of parsing a request head: either a request or the error
/// status to answer with.
pub const ParseResult = union(enum) {
    request: Request,
    reject: Status,
};

/// Parses a request head. `head` excludes the terminating CRLFCRLF. The
/// returned slices point into `head`.
pub fn parseHead(head: []const u8) ParseResult {
    const line_end = std.mem.indexOfScalar(u8, head, '\r') orelse head.len;
    const line = head[0..line_end];

    // Request line: method SP target SP version
    const sp1 = std.mem.indexOfScalar(u8, line, ' ') orelse return .{ .reject = .bad_request };
    if (sp1 == 0) return .{ .reject = .bad_request };
    const sp2 = std.mem.indexOfScalarPos(u8, line, sp1 + 1, ' ') orelse return .{ .reject = .bad_request };
    if (sp2 == sp1 + 1) return .{ .reject = .bad_request };

    const method = line[0..sp1];
    if (!isToken(method)) return .{ .reject = .bad_request };

    const version = line[sp2 + 1 ..];
    if (version.len != 8 or !std.mem.startsWith(u8, version, "HTTP/1.")) {
        return .{ .reject = if (std.mem.startsWith(u8, version, "HTTP/")) .http_version_not_supported else .bad_request };
    }

    var req: Request = .{ .method = method, .target = line[sp1 + 1 .. sp2] };
    var chunked = false;

    // Header fields, each preceded by CRLF.
    var pos = line_end;
    while (pos < head.len) {
        if (!std.mem.startsWith(u8, head[pos..], "\r\n")) return .{ .reject = .bad_request };
        pos += 2;
        const eol = std.mem.indexOfScalarPos(u8, head, pos, '\r') orelse head.len;
        const field = head[pos..eol];
        pos = eol;

        const colon = std.mem.indexOfScalar(u8, field, ':') orelse return .{ .reject = .bad_request };
        const name = field[0..colon];
        if (!isToken(name)) return .{ .reject = .bad_request };
        const value = std.mem.trim(u8, field[colon + 1 ..], " \t");

        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            const len = parseLength(value) orelse return .{ .reject = .bad_request };
            if (req.content_length) |prev| if (prev != len) return .{ .reject = .bad_request };
            req.content_length = len;
        } else if (std.ascii.eqlIgnoreCase(name, "Transfer-Encoding")) {
            chunked = true;
        }
    }

    if (chunked) return .{ .reject = if (req.content_length != null) .bad_request else .not_implemented };
    return .{ .request = req };
}

/// Parses a non-empty run of decimal digits, rejecting signs and overflow.
fn parseLength(s: []const u8) ?usize {
    if (s.len == 0) return null;
    for (s) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseUnsigned(usize, s, 10) catch null;
}

/// Whether `s` is a non-empty RFC 9110 token.
fn isToken(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", c) == null) return false;
    }
    return true;
}

pub const Response = struct {
    status: Status,
    content_type: ?[]const u8 = null,
    /// Value of the `Allow` header; set on 405 responses.
    allow: ?[]const u8 = null,
    body: []const u8 = "",

    pub fn write(r: Response, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("HTTP/1.1 {d} {s}\r\nContent-Length: {d}\r\nConnection: close\r\n", .{
            @intFromEnum(r.status), r.status.phrase() orelse "Unknown", r.body.len,
        });
        if (r.content_type) |ct| try w.print("Content-Type: {s}\r\n", .{ct});
        if (r.allow) |allow| try w.print("Allow: {s}\r\n", .{allow});
        try w.writeAll("\r\n");
        try w.writeAll(r.body);
        try w.flush();
    }
};

fn expectReject(status: Status, head: []const u8) !void {
    try std.testing.expectEqual(ParseResult{ .reject = status }, parseHead(head));
}

test parseHead {
    const ok = parseHead("PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length:  5 \r\nConnection: close");
    try std.testing.expectEqualStrings("PUT", ok.request.method);
    try std.testing.expectEqualStrings("/kv/a", ok.request.target);
    try std.testing.expectEqual(5, ok.request.content_length.?);

    try std.testing.expectEqual(null, parseHead("GET / HTTP/1.0").request.content_length);
    try expectReject(.bad_request, "GET /");
    try expectReject(.bad_request, " / HTTP/1.1");
    try expectReject(.bad_request, "GET  HTTP/1.1");
    try expectReject(.bad_request, "G@T / HTTP/1.1");
    try expectReject(.http_version_not_supported, "GET / HTTP/2.0");
    try expectReject(.bad_request, "GET / FTP/1.1");
    try expectReject(.bad_request, "GET / HTTP/1.1\r\nNoColon");
    try expectReject(.bad_request, "GET / HTTP/1.1\r\n: empty");
    try expectReject(.bad_request, "GET / HTTP/1.1\r\nContent-Length: -1");
    try expectReject(.bad_request, "GET / HTTP/1.1\r\nContent-Length: 99999999999999999999999");
    try expectReject(.bad_request, "GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2");
    try expectReject(.not_implemented, "GET / HTTP/1.1\r\nTransfer-Encoding: chunked");
    try expectReject(.bad_request, "GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 1");
}
