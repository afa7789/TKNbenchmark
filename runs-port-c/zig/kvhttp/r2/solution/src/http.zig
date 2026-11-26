//! Minimal HTTP/1.1 request parsing and response writing.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Status = std.http.Status;

/// Largest accepted request head (request line plus headers).
pub const head_max = 16 * 1024;

const chunk_line_max = 255;

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    /// Empty when the request has no body.
    body: []const u8,
};

/// Failures that are answered with an error status (see `statusFor`).
pub const RequestError = error{
    BadRequest,
    ContentTooLarge,
    ExpectationFailed,
    HeaderFieldsTooLarge,
    NotImplemented,
    VersionNotSupported,
    OutOfMemory,
};

/// The peer went away or timed out; no response should be attempted.
pub const ReadError = RequestError || error{ConnectionClosed};

pub fn statusFor(err: RequestError) Status {
    return switch (err) {
        error.BadRequest => .bad_request,
        error.ContentTooLarge => .payload_too_large,
        error.ExpectationFailed => .expectation_failed,
        error.HeaderFieldsTooLarge => .request_header_fields_too_large,
        error.NotImplemented => .not_implemented,
        error.VersionNotSupported => .http_version_not_supported,
        error.OutOfMemory => .internal_server_error,
    };
}

const Framing = struct {
    content_length: ?u64 = null,
    chunked: bool = false,
    expect_continue: bool = false,
};

/// Reads one request, accepting bodies up to `max_body` bytes. `in` must have
/// a buffer of at least `head_max` bytes. The interim `100 Continue` response
/// is written to `out` when the client asks for it. Everything returned is
/// allocated in `arena`.
pub fn readRequest(arena: Allocator, in: *Io.Reader, out: *Io.Writer, max_body: usize) ReadError!Request {
    std.debug.assert(in.buffer.len >= head_max);

    // The head is copied out of the reader buffer, which reading the body reuses.
    const head_len = try fillHead(in);
    const head = try arena.dupe(u8, in.buffered()[0..head_len]);
    in.toss(head_len);

    var lines = std.mem.splitScalar(u8, head, '\n');
    var request = try parseRequestLine(trimCr(lines.first()));
    const framing = try parseHeaders(&lines);

    if (framing.content_length) |len| if (len > max_body) return error.ContentTooLarge;
    if (framing.expect_continue and (framing.chunked or (framing.content_length orelse 0) > 0)) {
        out.writeAll("HTTP/1.1 100 Continue\r\n\r\n") catch return error.ConnectionClosed;
        out.flush() catch return error.ConnectionClosed;
    }

    if (framing.chunked) {
        request.body = try readChunked(arena, in, max_body);
    } else if (framing.content_length) |len| {
        const body = try arena.alloc(u8, @intCast(len));
        in.readSliceAll(body) catch return error.ConnectionClosed;
        request.body = body;
    }
    return request;
}

/// Buffers bytes until the blank line ending the head; returns its length.
fn fillHead(in: *Io.Reader) ReadError!usize {
    var scanned: usize = 0;
    while (true) {
        const buf = in.buffered();
        if (findHeadEnd(buf, scanned)) |end| return end;
        // Resume where the previous scan stopped, allowing for a split "\n\r\n".
        scanned = buf.len -| 2;
        if (buf.len >= head_max) return error.HeaderFieldsTooLarge;
        in.fillMore() catch return error.ConnectionClosed;
    }
}

/// Returns the offset just past the first "\n\n" or "\n\r\n" at or after `from`.
fn findHeadEnd(buf: []const u8, from: usize) ?usize {
    var i = from;
    while (std.mem.indexOfScalarPos(u8, buf, i, '\n')) |nl| : (i = nl + 1) {
        const rest = buf[nl + 1 ..];
        if (std.mem.startsWith(u8, rest, "\n")) return nl + 2;
        if (std.mem.startsWith(u8, rest, "\r\n")) return nl + 3;
    }
    return null;
}

fn parseRequestLine(line: []const u8) RequestError!Request {
    var parts = std.mem.splitScalar(u8, line, ' ');
    const method = parts.first();
    const target = parts.next() orelse return error.BadRequest;
    const version = parts.rest();
    if (parts.index == null) return error.BadRequest;

    if (method.len == 0 or target.len == 0) return error.BadRequest;
    if (!isToken(method)) return error.BadRequest;
    if (version.len != "HTTP/1.x".len or !std.mem.startsWith(u8, version, "HTTP/1.") or
        !std.ascii.isDigit(version[7]))
    {
        return if (std.mem.startsWith(u8, version, "HTTP/")) error.VersionNotSupported else error.BadRequest;
    }
    return .{ .method = method, .target = target, .body = "" };
}

fn parseHeaders(lines: *std.mem.SplitIterator(u8, .scalar)) RequestError!Framing {
    var framing: Framing = .{};
    while (lines.next()) |raw| {
        const line = trimCr(raw);
        if (line.len == 0) break;

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.BadRequest;
        const name = line[0..colon];
        if (name.len == 0 or !isToken(name)) return error.BadRequest;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            const len = parseUnsigned(value, 10) catch return error.BadRequest;
            if (framing.content_length) |prev| if (prev != len) return error.BadRequest;
            framing.content_length = len;
        } else if (std.ascii.eqlIgnoreCase(name, "Transfer-Encoding")) {
            if (!std.ascii.eqlIgnoreCase(value, "chunked")) return error.NotImplemented;
            framing.chunked = true;
        } else if (std.ascii.eqlIgnoreCase(name, "Expect")) {
            if (!std.ascii.eqlIgnoreCase(value, "100-continue")) return error.ExpectationFailed;
            framing.expect_continue = true;
        }
    }
    if (framing.chunked and framing.content_length != null) return error.BadRequest;
    return framing;
}

fn readChunked(arena: Allocator, in: *Io.Reader, max_body: usize) ReadError![]const u8 {
    var body: std.ArrayList(u8) = .empty;
    while (true) {
        const line = try readLine(in);
        const spec = std.mem.trim(u8, line[0 .. std.mem.indexOfScalar(u8, line, ';') orelse line.len], " \t");
        if (spec.len == 0) return error.BadRequest;
        const size = parseUnsigned(spec, 16) catch |err| return switch (err) {
            error.Overflow => error.ContentTooLarge,
            error.InvalidCharacter => error.BadRequest,
        };
        if (size == 0) break;
        if (size > max_body - body.items.len) return error.ContentTooLarge;

        const dest = try body.addManyAsSlice(arena, @intCast(size));
        in.readSliceAll(dest) catch return error.ConnectionClosed;
        if ((try readLine(in)).len != 0) return error.BadRequest;
    }
    // Trailer section: skip until the blank line.
    while ((try readLine(in)).len != 0) {}
    return body.items;
}

/// Reads one LF-terminated line, without the line terminator.
fn readLine(in: *Io.Reader) ReadError![]const u8 {
    const raw = in.takeDelimiterInclusive('\n') catch |err| return switch (err) {
        error.StreamTooLong => error.BadRequest,
        error.EndOfStream, error.ReadFailed => error.ConnectionClosed,
    };
    const line = raw[0 .. raw.len - 1];
    if (line.len > chunk_line_max) return error.BadRequest;
    return trimCr(line);
}

fn trimCr(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

/// Parses a non-empty run of digits. Unlike `std.fmt.parseUnsigned`, signs
/// and `_` separators are rejected, as HTTP requires.
fn parseUnsigned(s: []const u8, comptime base: u8) error{ InvalidCharacter, Overflow }!u64 {
    if (s.len == 0) return error.InvalidCharacter;
    var v: u64 = 0;
    for (s) |c| {
        const digit = try std.fmt.charToDigit(c, base);
        v = try std.math.mul(u64, v, base);
        v = try std.math.add(u64, v, digit);
    }
    return v;
}

fn isToken(s: []const u8) bool {
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c)) continue;
        if (std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", c) == null) return false;
    }
    return true;
}

/// Writes a complete response with Content-Length and `Connection: close`.
pub fn respond(out: *Io.Writer, status: Status, content_type: ?[]const u8, body: []const u8) Io.Writer.Error!void {
    try out.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase() orelse "Unknown" });
    if (content_type) |ct| try out.print("Content-Type: {s}\r\n", .{ct});
    try out.print("Content-Length: {d}\r\nConnection: close\r\n\r\n", .{body.len});
    try out.writeAll(body);
    try out.flush();
}

// ---------- tests ----------

const testing = std.testing;

fn parseFixed(arena: Allocator, raw: []const u8) ReadError!Request {
    var buf: [head_max]u8 = undefined;
    @memcpy(buf[0..raw.len], raw);
    var in: Io.Reader = .fixed(buf[0..raw.len]);
    in.buffer = &buf; // Give the reader its full capacity, as a socket reader would have.
    var discard: Io.Writer.Discarding = .init(&.{});
    return readRequest(arena, &in, &discard.writer, 1024);
}

test "parses a request with a Content-Length body" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = try parseFixed(arena.allocator(), "PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\n\r\nhello");
    try testing.expectEqualStrings("PUT", req.method);
    try testing.expectEqualStrings("/kv/a", req.target);
    try testing.expectEqualStrings("hello", req.body);
}

test "parses a chunked body" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req = try parseFixed(arena.allocator(), "PUT /kv/a HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n" ++
        "3;ext=1\r\nhel\r\n2\r\nlo\r\n0\r\nTrailer: x\r\n\r\n");
    try testing.expectEqualStrings("hello", req.body);
}

test "rejects malformed requests" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectError(error.BadRequest, parseFixed(a, "GET\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseFixed(a, "GET / HTTP/1.1\r\nBad Header: x\r\n\r\n"));
    try testing.expectError(error.BadRequest, parseFixed(a, "GET / HTTP/1.1\r\nContent-Length: +1\r\n\r\n"));
    try testing.expectError(error.VersionNotSupported, parseFixed(a, "GET / HTTP/2.0\r\n\r\n"));
    try testing.expectError(error.ContentTooLarge, parseFixed(a, "PUT / HTTP/1.1\r\nContent-Length: 1025\r\n\r\n"));
    try testing.expectError(error.NotImplemented, parseFixed(a, "PUT / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"));
    try testing.expectError(error.ConnectionClosed, parseFixed(a, "PUT / HTTP/1.1\r\nContent-Length: 9\r\n\r\nabc"));
}

test "findHeadEnd accepts bare LF" {
    try testing.expectEqual(@as(?usize, 7), findHeadEnd("GET /\n\nbody", 0));
    try testing.expectEqual(@as(?usize, 9), findHeadEnd("GET /\r\n\r\nbody", 0));
    try testing.expectEqual(@as(?usize, null), findHeadEnd("GET /\r\n", 0));
}
