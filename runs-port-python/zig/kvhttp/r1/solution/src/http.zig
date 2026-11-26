//! Minimal HTTP/1.1 request parsing and response serialization.
//!
//! Only what the key-value server needs: one request per connection, bodies
//! delimited by `Content-Length` or chunked transfer encoding.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const mem = std.mem;

pub const max_body_bytes = 1024 * 1024;
pub const max_head_bytes = 64 * 1024;

pub const Status = enum(u10) {
    ok = 200,
    created = 201,
    no_content = 204,
    bad_request = 400,
    not_found = 404,
    method_not_allowed = 405,
    content_too_large = 413,
    request_header_fields_too_large = 431,
    internal_server_error = 500,

    pub fn phrase(s: Status) []const u8 {
        return switch (s) {
            .ok => "OK",
            .created => "Created",
            .no_content => "No Content",
            .bad_request => "Bad Request",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .content_too_large => "Content Too Large",
            .request_header_fields_too_large => "Request Header Fields Too Large",
            .internal_server_error => "Internal Server Error",
        };
    }

    /// Responses with these statuses never carry a body or `Content-Length`.
    fn isBodiless(s: Status) bool {
        return s == .no_content;
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Response = struct {
    status: Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    allow: ?[]const u8 = null,

    pub fn write(r: Response, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(r.status), r.status.phrase() });
        if (!r.status.isBodiless()) try w.print("Content-Length: {d}\r\n", .{r.body.len});
        try w.writeAll("Connection: close\r\n");
        if (r.content_type) |v| try w.print("Content-Type: {s}\r\n", .{v});
        if (r.allow) |v| try w.print("Allow: {s}\r\n", .{v});
        try w.writeAll("\r\n");
        if (!r.status.isBodiless()) try w.writeAll(r.body);
        try w.flush();
    }
};

pub const Request = struct {
    method: []const u8,
    /// Request target with any query string removed.
    path: []const u8,
    body: []const u8,
};

/// Protocol violations that are answered with an error status.
pub const ProtocolError = error{
    BadRequest,
    ContentTooLarge,
    HeaderFieldsTooLarge,
};

pub const ReadError = ProtocolError || Allocator.Error || Io.Reader.Error;

pub fn statusFor(err: ProtocolError) Status {
    return switch (err) {
        error.BadRequest => .bad_request,
        error.ContentTooLarge => .content_too_large,
        error.HeaderFieldsTooLarge => .request_header_fields_too_large,
    };
}

/// Reads one request from `r`. All returned slices are allocated with
/// `arena`. The reader's buffer must be at least `max_head_bytes` long.
pub fn readRequest(arena: Allocator, r: *Io.Reader) ReadError!Request {
    const head_len = try findHeadEnd(r);
    const head = try arena.dupe(u8, r.buffered()[0 .. head_len - 4]);
    r.toss(head_len);

    var lines = mem.splitSequence(u8, head, "\r\n");
    const request_line = lines.first();

    var parts = mem.splitScalar(u8, request_line, ' ');
    const method = parts.next().?;
    const target = parts.next() orelse return error.BadRequest;
    const version = parts.next() orelse return error.BadRequest;
    if (parts.next() != null or !mem.startsWith(u8, version, "HTTP/")) return error.BadRequest;

    var content_length: ?[]const u8 = null;
    var transfer_encoding: ?[]const u8 = null;
    while (lines.next()) |line| {
        const header = try parseHeaderLine(line);
        // Later duplicates win, as with a dictionary keyed by lowercase name.
        if (std.ascii.eqlIgnoreCase(header.name, "content-length")) {
            content_length = header.value;
        } else if (std.ascii.eqlIgnoreCase(header.name, "transfer-encoding")) {
            transfer_encoding = header.value;
        }
    }

    const body = if (transfer_encoding != null and std.ascii.indexOfIgnoreCase(transfer_encoding.?, "chunked") != null)
        try readChunkedBody(arena, r)
    else blk: {
        const length = try parseContentLength(content_length orelse "0");
        const body = try arena.alloc(u8, length);
        try r.readSliceAll(body);
        break :blk body;
    };

    const path = if (mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;
    return .{ .method = method, .path = path, .body = body };
}

/// Fills `r` until its buffer holds the full request head; returns the
/// head's length including the terminating blank line.
fn findHeadEnd(r: *Io.Reader) (ProtocolError || Io.Reader.Error)!usize {
    const terminator = "\r\n\r\n";
    var scanned: usize = 0;
    while (true) {
        const buf = r.buffered();
        if (mem.indexOfPos(u8, buf, scanned, terminator)) |i| return i + terminator.len;
        scanned = buf.len -| (terminator.len - 1);
        if (buf.len >= max_head_bytes or buf.len == r.buffer.len) return error.HeaderFieldsTooLarge;
        try r.fillMore();
    }
}

fn parseHeaderLine(line: []const u8) ProtocolError!Header {
    const colon = mem.indexOfScalar(u8, line, ':') orelse return error.BadRequest;
    const name = line[0..colon];
    if (name.len == 0 or isSpace(name[0]) or isSpace(name[name.len - 1])) return error.BadRequest;
    return .{ .name = name, .value = mem.trim(u8, line[colon + 1 ..], &whitespace) };
}

const whitespace = [_]u8{ ' ', '\t', '\r', '\n', 0x0b, 0x0c };

fn isSpace(c: u8) bool {
    return mem.indexOfScalar(u8, &whitespace, c) != null;
}

fn parseContentLength(raw: []const u8) ProtocolError!usize {
    if (raw.len == 0) return error.BadRequest;
    for (raw) |c| if (!std.ascii.isDigit(c)) return error.BadRequest;
    const length = std.fmt.parseUnsigned(usize, raw, 10) catch return error.ContentTooLarge;
    if (length > max_body_bytes) return error.ContentTooLarge;
    return length;
}

fn readChunkedBody(arena: Allocator, r: *Io.Reader) ReadError![]u8 {
    var body: std.ArrayList(u8) = .empty;
    while (true) {
        const line = try takeLine(r);
        const size_text = mem.trim(u8, line[0 .. mem.indexOfScalar(u8, line, ';') orelse line.len], &whitespace);
        const size = std.fmt.parseUnsigned(usize, size_text, 16) catch |err| switch (err) {
            error.Overflow => return error.ContentTooLarge,
            error.InvalidCharacter => return error.BadRequest,
        };
        if (size == 0) {
            // Skip trailers up to the terminating blank line.
            while ((try takeLine(r)).len != 0) {}
            return body.items;
        }
        if (body.items.len + size > max_body_bytes) return error.ContentTooLarge;
        try r.readSliceAll(try body.addManyAsSlice(arena, size));
        if (!mem.eql(u8, try r.takeArray(2), "\r\n")) return error.BadRequest;
    }
}

/// Takes one CRLF-terminated line, returned without the terminator.
fn takeLine(r: *Io.Reader) (ProtocolError || Io.Reader.Error)![]u8 {
    const line = r.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.StreamTooLong => return error.HeaderFieldsTooLarge,
        else => |e| return e,
    };
    if (line.len < 2 or line[line.len - 2] != '\r') return error.BadRequest;
    return line[0 .. line.len - 2];
}

const testing = std.testing;

fn parseFixed(arena: Allocator, raw: []const u8) ReadError!Request {
    var reader: Io.Reader = .fixed(raw);
    return readRequest(arena, &reader);
}

test "content-length request" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = try parseFixed(arena.allocator(), "PUT /kv/a?x=1 HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\n\r\nhello");
    try testing.expectEqualStrings("PUT", req.method);
    try testing.expectEqualStrings("/kv/a", req.path);
    try testing.expectEqualStrings("hello", req.body);
}

test "chunked request" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = try parseFixed(arena.allocator(), "PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n" ++
        "3\r\nabc\r\n2;ext=1\r\nde\r\n0\r\nTrailer: x\r\n\r\n");
    try testing.expectEqualStrings("abcde", req.body);
}

test "malformed requests" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectError(error.BadRequest, parseFixed(a, "GET /\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseFixed(a, "GET / FTP/1\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseFixed(a, "GET / HTTP/1.1\r\nnocolon\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseFixed(a, "GET / HTTP/1.1\r\n x: y\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseFixed(a, "GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"));
    try testing.expectError(error.ContentTooLarge, parseFixed(a, "GET / HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n"));
    try testing.expectError(error.ContentTooLarge, parseFixed(a, "GET / HTTP/1.1\r\nContent-Length: 99999999999999999999999\r\n\r\n"));
}

test "response serialization" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try (Response{ .status = .ok, .body = "ok", .content_type = "text/plain" }).write(&w);
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\nok", w.buffered());

    w = .fixed(&buf);
    try (Response{ .status = .no_content }).write(&w);
    try testing.expectEqualStrings("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n", w.buffered());
}
