//! Minimal HTTP/1.1 request parser and response serialiser.
//!
//! One request is served per connection, so there is no keep-alive or
//! pipelining support: every response carries `Connection: close`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Status = std.http.Status;

pub const max_header_bytes = 64 * 1024;
pub const max_body_bytes = 1024 * 1024;

/// Size of the read buffer a connection must provide; it bounds the length of
/// a single request or header line.
pub const read_buffer_len = max_header_bytes + 1024;

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    headers: []const Header,
    body: []const u8,

    /// Case-insensitive header lookup; returns the first match.
    pub fn header(req: *const Request, name: []const u8) ?[]const u8 {
        for (req.headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
        }
        return null;
    }
};

pub const Response = struct {
    status: Status = .ok,
    content_type: ?[]const u8 = null,
    body: []const u8 = "",

    pub fn empty(status: Status) Response {
        return .{ .status = status };
    }
};

/// Reasons a request could not be read. Each maps to a response status via
/// `errorStatus`.
pub const ReadError = error{
    BadRequest,
    HeaderFieldsTooLarge,
    ContentTooLarge,
    NotImplemented,
    /// The underlying reader failed (timeout, reset, ...).
    ReadFailed,
    OutOfMemory,
};

pub fn errorStatus(err: ReadError) Status {
    return switch (err) {
        error.BadRequest => .bad_request,
        error.HeaderFieldsTooLarge => .request_header_fields_too_large,
        error.ContentTooLarge => .payload_too_large,
        error.NotImplemented => .not_implemented,
        error.ReadFailed => .request_timeout,
        error.OutOfMemory => .internal_server_error,
    };
}

/// Reads one request. Returns null if the peer closed the connection before
/// sending anything. All returned memory is allocated with `arena`.
pub fn readRequest(arena: Allocator, r: *Io.Reader) ReadError!?Request {
    r.fill(1) catch |err| switch (err) {
        error.EndOfStream => return null,
        error.ReadFailed => return error.ReadFailed,
    };

    // Tolerate stray blank lines before the request line (RFC 9112 §2.2).
    var request_line = try readLine(r);
    while (request_line.len == 0) request_line = try readLine(r);
    var header_bytes: usize = request_line.len;

    const sp1 = std.mem.indexOfScalar(u8, request_line, ' ') orelse return error.BadRequest;
    const sp2 = std.mem.indexOfScalarPos(u8, request_line, sp1 + 1, ' ') orelse return error.BadRequest;
    if (sp1 == 0 or sp2 == sp1 + 1) return error.BadRequest;
    if (!std.mem.startsWith(u8, request_line[sp2 + 1 ..], "HTTP/")) return error.BadRequest;
    const method = try arena.dupe(u8, request_line[0..sp1]);
    const target = try arena.dupe(u8, request_line[sp1 + 1 .. sp2]);

    var headers: std.ArrayList(Header) = .empty;
    while (true) {
        const line = try readLine(r);
        if (line.len == 0) break;
        header_bytes += line.len;
        if (header_bytes > max_header_bytes) return error.HeaderFieldsTooLarge;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.BadRequest;
        if (colon == 0) return error.BadRequest;
        try headers.append(arena, .{
            .name = try arena.dupe(u8, line[0..colon]),
            .value = try arena.dupe(u8, trim(line[colon + 1 ..])),
        });
    }

    var req: Request = .{
        .method = method,
        .target = target,
        .headers = headers.items,
        .body = "",
    };

    if (req.header("Transfer-Encoding")) |te| {
        if (!std.ascii.eqlIgnoreCase(te, "chunked")) return error.NotImplemented;
        req.body = try readChunkedBody(arena, r);
    } else if (req.header("Content-Length")) |cl| {
        const len = try parseSize(cl, 10);
        if (len > max_body_bytes) return error.ContentTooLarge;
        req.body = r.readAlloc(arena, len) catch |err| switch (err) {
            error.EndOfStream => return error.BadRequest,
            error.ReadFailed => return error.ReadFailed,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }
    return req;
}

fn readChunkedBody(arena: Allocator, r: *Io.Reader) ReadError![]const u8 {
    var body: std.ArrayList(u8) = .empty;
    while (true) {
        const line = try readLine(r);
        const size_part = if (std.mem.indexOfScalar(u8, line, ';')) |semi| line[0..semi] else line;
        const size = try parseSize(trim(size_part), 16);
        if (size == 0) break;
        if (size > max_body_bytes - body.items.len) return error.ContentTooLarge;
        const dest = try body.addManyAsSlice(arena, size);
        r.readSliceAll(dest) catch |err| switch (err) {
            error.EndOfStream => return error.BadRequest,
            error.ReadFailed => return error.ReadFailed,
        };
        if ((try readLine(r)).len != 0) return error.BadRequest;
    }
    // Trailer section, terminated by an empty line.
    var trailer_bytes: usize = 0;
    while (true) {
        const line = try readLine(r);
        if (line.len == 0) break;
        trailer_bytes += line.len;
        if (trailer_bytes > max_header_bytes) return error.HeaderFieldsTooLarge;
    }
    return body.items;
}

/// Returns the next line without its CRLF (or bare LF) terminator. The slice
/// points into the reader's buffer and is invalidated by the next read.
fn readLine(r: *Io.Reader) ReadError![]const u8 {
    const line = r.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.HeaderFieldsTooLarge,
        error.EndOfStream => return error.BadRequest,
        error.ReadFailed => return error.ReadFailed,
    };
    const without_lf = line[0 .. line.len - 1];
    return std.mem.trimEnd(u8, without_lf, "\r");
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t");
}

/// Strict unsigned parse: digits only, no sign, no separators, no overflow.
fn parseSize(s: []const u8, base: u8) error{BadRequest}!usize {
    if (s.len == 0) return error.BadRequest;
    var value: usize = 0;
    for (s) |c| {
        const digit = std.fmt.charToDigit(c, base) catch return error.BadRequest;
        value = std.math.mul(usize, value, base) catch return error.BadRequest;
        value = std.math.add(usize, value, digit) catch return error.BadRequest;
    }
    return value;
}

/// Serialises `res`, always with `Connection: close`, and flushes `w`.
pub fn writeResponse(w: *Io.Writer, res: Response) Io.Writer.Error!void {
    try w.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(res.status), res.status.phrase() orelse "Unknown" });
    if (res.content_type) |content_type| {
        try w.print("Content-Type: {s}\r\n", .{content_type});
    }
    // 204 must not carry a body or Content-Length framing; everything else
    // advertises its exact length.
    if (res.status != .no_content) {
        try w.print("Content-Length: {d}\r\n", .{res.body.len});
    }
    try w.writeAll("Connection: close\r\n\r\n");
    try w.writeAll(res.body);
    try w.flush();
}

fn testParse(arena: Allocator, raw: []const u8) ReadError!?Request {
    const buf = try arena.alloc(u8, read_buffer_len);
    var stream: Io.Reader = .fixed(raw);
    // Route through a buffered reader so line limits behave as on a socket.
    var limited = stream.limited(.unlimited, buf);
    return readRequest(arena, &limited.interface);
}

test "parses request line, headers and body" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const req = (try testParse(arena.allocator(), "\r\nPUT /kv/a HTTP/1.1\r\ncontent-length: 5\r\nHost:  x \r\n\r\nhello")).?;
    try std.testing.expectEqualStrings("PUT", req.method);
    try std.testing.expectEqualStrings("/kv/a", req.target);
    try std.testing.expectEqualStrings("x", req.header("host").?);
    try std.testing.expectEqualStrings("hello", req.body);
}

test "parses chunked body" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const raw = "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5;ext=1\r\nhello\r\n6\r\n world\r\n0\r\nX: y\r\n\r\n";
    const req = (try testParse(arena.allocator(), raw)).?;
    try std.testing.expectEqualStrings("hello world", req.body);
}

test "rejects malformed requests" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(null, try testParse(a, ""));
    try std.testing.expectError(error.BadRequest, testParse(a, "GET /\r\n\r\n"));
    try std.testing.expectError(error.BadRequest, testParse(a, "GET  / HTTP/1.1\r\n\r\n"));
    try std.testing.expectError(error.BadRequest, testParse(a, "GET / FTP/1.1\r\n\r\n"));
    try std.testing.expectError(error.BadRequest, testParse(a, "GET / HTTP/1.1\r\nnocolon\r\n\r\n"));
    try std.testing.expectError(error.BadRequest, testParse(a, "PUT / HTTP/1.1\r\nContent-Length: +5\r\n\r\nhello"));
    try std.testing.expectError(error.BadRequest, testParse(a, "PUT / HTTP/1.1\r\nContent-Length: 9\r\n\r\nhello"));
    try std.testing.expectError(error.ContentTooLarge, testParse(a, "PUT / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n"));
    try std.testing.expectError(error.NotImplemented, testParse(a, "PUT / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"));
}

test "serialises responses" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeResponse(&w, .{ .status = .ok, .content_type = "text/plain", .body = "ok" });
    try std.testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
        w.buffered(),
    );

    w = .fixed(&buf);
    try writeResponse(&w, .empty(.no_content));
    try std.testing.expectEqualStrings("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n", w.buffered());
}
