//! Minimal HTTP/1.1 request parsing and response serialization.
//!
//! The server handles exactly one request per connection, so the parser only
//! needs to read a single request head and its body.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Status = std.http.Status;

/// Upper bound on the request line plus headers, including the blank line.
pub const max_header_bytes = 64 * 1024;
/// Upper bound on a request body.
pub const max_body_bytes = 1024 * 1024;

pub const Request = struct {
    method: []const u8,
    /// Request target with any query string removed.
    path: []const u8,
    body: []const u8,
};

pub const Response = struct {
    status: Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    allow: ?[]const u8 = null,

    pub fn write(r: Response, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(r.status), reasonPhrase(r.status) });
        if (r.content_type) |value| try w.print("Content-Type: {s}\r\n", .{value});
        if (r.allow) |value| try w.print("Allow: {s}\r\n", .{value});
        try w.print("Content-Length: {d}\r\nConnection: close\r\n\r\n", .{r.body.len});
        try w.writeAll(r.body);
    }
};

fn reasonPhrase(status: Status) []const u8 {
    return switch (status) {
        .payload_too_large => "Content Too Large", // RFC 9110 name
        else => status.phrase() orelse "",
    };
}

/// Protocol violations that are answered with an error response.
pub const ProtocolError = error{
    BadRequest,
    HeaderTooLarge,
    ContentTooLarge,
    NotImplemented,
};

pub fn statusFor(err: ProtocolError) Status {
    return switch (err) {
        error.BadRequest => .bad_request,
        error.HeaderTooLarge => .request_header_fields_too_large,
        error.ContentTooLarge => .payload_too_large,
        error.NotImplemented => .not_implemented,
    };
}

pub const ReadError = ProtocolError || Allocator.Error || Io.Reader.Error;

/// Reads one request from `r`, whose buffer must hold at least
/// `max_header_bytes`. Method, path, and body are allocated with
/// `arena`, so they remain valid after the reader's buffer is reused.
///
/// `error.EndOfStream` and `error.ReadFailed` mean the client went away
/// before sending a complete request.
pub fn readRequest(r: *Io.Reader, arena: Allocator) ReadError!Request {
    const head_len = try fillHead(r);
    const head = r.buffered()[0..head_len];

    var lines = std.mem.splitSequence(u8, head, "\r\n");
    var parts = std.mem.splitScalar(u8, lines.first(), ' ');
    const method = parts.first();
    const target = parts.next() orelse return error.BadRequest;
    const version = parts.next() orelse return error.BadRequest;
    if (parts.next() != null or !std.mem.startsWith(u8, version, "HTTP/")) return error.BadRequest;

    // Only the framing headers matter to this server. Later duplicates win.
    var content_length: ?[]const u8 = null;
    var transfer_encoding: ?[]const u8 = null;
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.BadRequest;
        const name = line[0..colon];
        if (name.len == 0 or std.mem.trim(u8, name, &std.ascii.whitespace).len != name.len)
            return error.BadRequest;
        const value = std.mem.trim(u8, line[colon + 1 ..], &std.ascii.whitespace);
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            content_length = value;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            transfer_encoding = value;
        }
    }

    const path_end = std.mem.indexOfScalar(u8, target, '?') orelse target.len;
    const request: Request = .{
        .method = try arena.dupe(u8, method),
        .path = try arena.dupe(u8, target[0..path_end]),
        .body = "",
    };

    // Validate framing before consuming the head; the head slices above
    // alias the reader buffer and are invalidated by further reads.
    const framing: Framing = if (transfer_encoding) |te| blk: {
        if (!std.ascii.eqlIgnoreCase(te, "chunked")) return error.NotImplemented;
        break :blk .chunked;
    } else if (content_length) |cl| .{ .length = try parseContentLength(cl) } else .{ .length = 0 };

    r.toss(head_len + 4);

    var result = request;
    result.body = switch (framing) {
        .length => |n| try r.readAlloc(arena, n),
        .chunked => try readChunked(r, arena),
    };
    return result;
}

const Framing = union(enum) {
    length: usize,
    chunked,
};

/// Buffers input until the head terminator is seen; returns the head length
/// excluding the terminating "\r\n\r\n". Stream readers must have a buffer of
/// at least `max_header_bytes`.
fn fillHead(r: *Io.Reader) (ProtocolError || Io.Reader.Error)!usize {
    const terminator = "\r\n\r\n";
    var scanned: usize = 0;
    while (true) {
        const buffered = r.buffered();
        if (std.mem.indexOfPos(u8, buffered, scanned, terminator)) |end| return end;
        scanned = buffered.len -| (terminator.len - 1);
        if (buffered.len >= max_header_bytes) return error.HeaderTooLarge;
        try r.fillMore();
    }
}

fn parseContentLength(text: []const u8) ProtocolError!usize {
    if (text.len == 0) return error.BadRequest;
    for (text) |c| if (!std.ascii.isDigit(c)) return error.BadRequest;
    const n = std.fmt.parseInt(usize, text, 10) catch |err| switch (err) {
        error.Overflow => return error.ContentTooLarge,
        error.InvalidCharacter => unreachable, // digits checked above
    };
    if (n > max_body_bytes) return error.ContentTooLarge;
    return n;
}

fn readChunked(r: *Io.Reader, arena: Allocator) ReadError![]u8 {
    var body: std.ArrayList(u8) = .empty;
    while (true) {
        const line = try takeLine(r);
        const size_end = std.mem.indexOfScalar(u8, line, ';') orelse line.len;
        const size_text = std.mem.trim(u8, line[0..size_end], &std.ascii.whitespace);
        const size = std.fmt.parseInt(usize, size_text, 16) catch |err| switch (err) {
            error.Overflow => return error.ContentTooLarge,
            error.InvalidCharacter => return error.BadRequest,
        };
        if (size == 0) {
            // Discard trailers up to the terminating blank line.
            while ((try takeLine(r)).len != 0) {}
            return body.toOwnedSlice(arena);
        }
        if (size > max_body_bytes - body.items.len) return error.ContentTooLarge;
        try r.readSliceAll(try body.addManyAsSlice(arena, size));
        if (!std.mem.eql(u8, try r.take(2), "\r\n")) return error.BadRequest;
    }
}

/// Takes one CRLF-terminated line, returning it without the terminator.
fn takeLine(r: *Io.Reader) (ProtocolError || Io.Reader.Error)![]u8 {
    const line = r.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.BadRequest,
        else => |e| return e,
    };
    if (line.len < 2 or line[line.len - 2] != '\r') return error.BadRequest;
    return line[0 .. line.len - 2];
}

const testing = std.testing;

fn parse(arena: Allocator, raw: []const u8) ReadError!Request {
    var r: Io.Reader = .fixed(raw);
    return readRequest(&r, arena);
}

test "parses request with content length" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = try parse(arena.allocator(), "PUT /kv/a?x=1 HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\n\r\nhello");
    try testing.expectEqualStrings("PUT", req.method);
    try testing.expectEqualStrings("/kv/a", req.path);
    try testing.expectEqualStrings("hello", req.body);
}

test "parses chunked body" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = try parse(arena.allocator(), "PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: Chunked\r\n\r\n" ++
        "5;ext=1\r\nhello\r\n6\r\n world\r\n0\r\nTrailer: x\r\n\r\n");
    try testing.expectEqualStrings("hello world", req.body);
}

test "rejects malformed requests" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectError(error.BadRequest, parse(a, "GET /\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse(a, "GET / FTP/1.0\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse(a, "GET  / HTTP/1.1\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse(a, "GET / HTTP/1.1\r\nNoColon\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse(a, "GET / HTTP/1.1\r\nName : v\r\n\r\n"));
    try testing.expectError(error.BadRequest, parse(a, "GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"));
    try testing.expectError(error.ContentTooLarge, parse(a, "GET / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n"));
    try testing.expectError(error.NotImplemented, parse(a, "GET / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"));
    try testing.expectError(error.EndOfStream, parse(a, "GET / HTTP/1.1\r\nContent-Length: 4\r\n\r\nab"));
    try testing.expectError(error.EndOfStream, parse(a, "GET / HTTP/1.1\r\n"));
}

test "serializes response" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try (Response{ .status = .method_not_allowed, .allow = "GET" }).write(&w);
    try testing.expectEqualStrings(
        "HTTP/1.1 405 Method Not Allowed\r\nAllow: GET\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        w.buffered(),
    );
}
