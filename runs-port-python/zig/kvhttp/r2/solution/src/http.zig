//! Minimal HTTP/1.1 request parsing and response serialization.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const max_body_size = 1024 * 1024;
/// Upper bound for the request head and for each chunk-size line. The
/// connection reader's buffer must be at least this large.
pub const max_head_size = 64 * 1024;

pub const Status = enum(u16) {
    ok = 200,
    created = 201,
    no_content = 204,
    bad_request = 400,
    not_found = 404,
    method_not_allowed = 405,
    content_too_large = 413,
    request_header_fields_too_large = 431,
    internal_server_error = 500,

    pub fn phrase(status: Status) []const u8 {
        return switch (status) {
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
};

pub const Request = struct {
    method: []const u8,
    /// Request target with any query string removed.
    path: []const u8,
    body: []u8,
};

pub const Response = struct {
    status: Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    allow: ?[]const u8 = null,

    pub fn write(res: Response, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("HTTP/1.1 {d} {s}\r\nConnection: close\r\n", .{ @intFromEnum(res.status), res.status.phrase() });
        if (res.allow) |allow| try w.print("Allow: {s}\r\n", .{allow});
        if (res.content_type) |ct| {
            try w.print("Content-Type: {s}\r\n", .{ct});
        } else if (res.body.len != 0) {
            try w.writeAll("Content-Type: application/octet-stream\r\n");
        }
        try w.print("Content-Length: {d}\r\n\r\n", .{res.body.len});
        try w.writeAll(res.body);
        try w.flush();
    }
};

pub const ParseError = error{
    /// Malformed request; answer 400.
    BadRequest,
    /// Request head exceeds `max_head_size`; answer 431.
    HeaderTooLarge,
    /// Body exceeds `max_body_size`; answer 413.
    ContentTooLarge,
    /// The underlying connection failed; no response can be delivered.
    ReadFailed,
    OutOfMemory,
};

pub fn errorStatus(err: ParseError) ?Status {
    return switch (err) {
        error.BadRequest => .bad_request,
        error.HeaderTooLarge => .request_header_fields_too_large,
        error.ContentTooLarge => .content_too_large,
        error.OutOfMemory => .internal_server_error,
        error.ReadFailed => null,
    };
}

/// Reads one request from `r`. Returns null if the peer closed the
/// connection without sending anything but whitespace.
///
/// `method` and `path` are allocated with `arena`; `body` is allocated with
/// `gpa` and owned by the caller.
pub fn readRequest(arena: Allocator, gpa: Allocator, r: *Io.Reader) ParseError!?Request {
    std.debug.assert(r.buffer.len >= max_head_size);

    const head = try readHead(r) orelse return null;

    var lines = std.mem.splitSequence(u8, head, "\r\n");
    const request_line = lines.first();
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next().?;
    const target = parts.next() orelse return error.BadRequest;
    _ = parts.next() orelse return error.BadRequest;
    if (parts.next() != null) return error.BadRequest;

    var content_length: ?[]const u8 = null;
    var transfer_encoding: []const u8 = "";
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.BadRequest;
        const name = trim(line[0..colon]);
        const value = trim(line[colon + 1 ..]);
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            content_length = value;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            transfer_encoding = value;
        }
    }

    const path_end = std.mem.indexOfScalar(u8, target, '?') orelse target.len;
    // Copy before reading the body: further reads may overwrite the buffer `head` points into.
    const owned_method = try arena.dupe(u8, method);
    const owned_path = try arena.dupe(u8, target[0..path_end]);
    const is_chunked = std.ascii.indexOfIgnoreCase(transfer_encoding, "chunked") != null;
    const length = if (content_length) |cl| try parseContentLength(cl) else null;

    const body = if (is_chunked)
        try readChunkedBody(gpa, r)
    else if (length) |n|
        try readSizedBody(gpa, r, n)
    else
        try gpa.alloc(u8, 0);

    return .{ .method = owned_method, .path = owned_path, .body = body };
}

/// Returns the request head including its terminating blank line, consumed
/// from `r`. The slice is valid until the next read from `r`.
fn readHead(r: *Io.Reader) ParseError!?[]const u8 {
    const terminator = "\r\n\r\n";
    var search_from: usize = 0;
    while (true) {
        const buffered = r.buffered();
        if (std.mem.indexOfPos(u8, buffered, search_from, terminator)) |i| {
            const head = buffered[0 .. i + terminator.len];
            r.toss(head.len);
            return head;
        }
        if (buffered.len >= max_head_size) return error.HeaderTooLarge;
        search_from = buffered.len -| (terminator.len - 1);
        r.fillMore() catch |err| switch (err) {
            error.EndOfStream => {
                if (trim(r.buffered()).len == 0) return null;
                return error.BadRequest;
            },
            error.ReadFailed => return error.ReadFailed,
        };
    }
}

fn parseContentLength(text: []const u8) ParseError!u64 {
    if (text.len == 0) return error.BadRequest;
    for (text) |c| if (!std.ascii.isDigit(c)) return error.BadRequest;
    // All digits: the only possible failure is overflow, which is simply "too large".
    return std.fmt.parseInt(u64, text, 10) catch std.math.maxInt(u64);
}

fn readSizedBody(gpa: Allocator, r: *Io.Reader, length: u64) ParseError![]u8 {
    if (length > max_body_size) {
        // Drain the body so the client reliably receives the error response.
        r.discardAll64(length) catch |err| return mapReadError(err);
        return error.ContentTooLarge;
    }
    const body = try gpa.alloc(u8, @intCast(length));
    errdefer gpa.free(body);
    r.readSliceAll(body) catch |err| return mapReadError(err);
    return body;
}

fn readChunkedBody(gpa: Allocator, r: *Io.Reader) ParseError![]u8 {
    var body: std.ArrayList(u8) = .empty;
    errdefer body.deinit(gpa);
    while (true) {
        const line = try takeLine(r);
        const size_text = trim(line[0 .. std.mem.indexOfScalar(u8, line, ';') orelse line.len]);
        const size = std.fmt.parseInt(usize, size_text, 16) catch |err| switch (err) {
            error.Overflow => return error.ContentTooLarge,
            error.InvalidCharacter => return error.BadRequest,
        };
        if (size == 0) {
            // Consume optional trailers up to the terminating blank line.
            while ((try takeLine(r)).len != 0) {}
            return body.toOwnedSlice(gpa);
        }
        if (body.items.len + size > max_body_size) return error.ContentTooLarge;
        r.readSliceAll(try body.addManyAsSlice(gpa, size)) catch |err| return mapReadError(err);
        r.discardAll(2) catch |err| return mapReadError(err);
    }
}

/// Takes one CRLF-terminated line, returning it without the CRLF.
fn takeLine(r: *Io.Reader) ParseError![]const u8 {
    var search_from: usize = 0;
    while (true) {
        const buffered = r.buffered();
        if (std.mem.indexOfPos(u8, buffered, search_from, "\r\n")) |i| {
            r.toss(i + 2);
            return buffered[0..i];
        }
        if (buffered.len >= max_head_size) return error.BadRequest;
        search_from = buffered.len -| 1;
        r.fillMore() catch |err| return mapReadError(err);
    }
}

fn mapReadError(err: Io.Reader.Error) ParseError {
    return switch (err) {
        error.EndOfStream => error.BadRequest,
        error.ReadFailed => error.ReadFailed,
    };
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n\x0b\x0c");
}

const testing = std.testing;

/// Parses `input` with all allocations in `arena`.
fn parseFixed(arena: Allocator, input: []const u8) ParseError!?Request {
    const buf = try arena.alloc(u8, max_head_size);
    var src: Io.Reader = .fixed(input);
    var r = src.limited(.unlimited, buf);
    return readRequest(arena, arena, &r.interface);
}

fn expectRequest(input: []const u8, method: []const u8, path: []const u8, body: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = (try parseFixed(arena.allocator(), input)).?;
    try testing.expectEqualStrings(method, req.method);
    try testing.expectEqualStrings(path, req.path);
    try testing.expectEqualStrings(body, req.body);
}

fn expectParseError(expected: ParseError, input: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(expected, parseFixed(arena.allocator(), input));
}

fn expectNoRequest(input: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(null, try parseFixed(arena.allocator(), input));
}

test "parse simple requests" {
    try expectRequest("GET /health HTTP/1.1\r\nHost: x\r\n\r\n", "GET", "/health", "");
    try expectRequest("PUT /kv/a?x=1 HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello", "PUT", "/kv/a", "hello");
    try expectRequest("PUT /kv/a HTTP/1.1\r\ncontent-length:  3 \r\n\r\nabcdef", "PUT", "/kv/a", "abc");
}

test "parse chunked body" {
    try expectRequest(
        "PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: Chunked\r\n\r\n5;ext=1\r\nhello\r\n6\r\n world\r\n0\r\nX-T: 1\r\n\r\n",
        "PUT",
        "/kv/a",
        "hello world",
    );
}

test "parse errors" {
    try expectNoRequest("");
    try expectNoRequest(" \r\n");
    try expectParseError(error.BadRequest, "GET /\r\n\r\n");
    try expectParseError(error.BadRequest, "GET / HTTP/1.1 x\r\n\r\n");
    try expectParseError(error.BadRequest, "GET / HTTP/1.1\r\nnocolon\r\n\r\n");
    try expectParseError(error.BadRequest, "GET / HTTP/1.1\r\nHost: x\r\n");
    try expectParseError(error.BadRequest, "PUT / HTTP/1.1\r\nContent-Length: -1\r\n\r\n");
    try expectParseError(error.BadRequest, "PUT / HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort");
    try expectParseError(error.BadRequest, "PUT / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n");
    try expectParseError(error.BadRequest, "PUT / HTTP/1.1\r\nContent-Length: 2000000\r\n\r\nabc");
}

test "oversized head" {
    const input = try testing.allocator.alloc(u8, max_head_size + 10);
    defer testing.allocator.free(input);
    @memset(input, 'a');
    try expectParseError(error.HeaderTooLarge, input);
}

test "response serialization" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try (Response{ .status = .ok, .body = "ok", .content_type = "text/plain" }).write(&w);
    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\nok",
        w.buffered(),
    );
}
