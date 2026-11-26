//! Minimal HTTP/1.1 request reader and response writer: one request per
//! connection, `Content-Length` bodies only.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Status = std.http.Status;

/// Limits applied while reading a request.
pub const Limits = struct {
    max_header_bytes: usize = 64 * 1024,
    max_body_bytes: usize = 1024 * 1024,

    /// Smallest reader buffer that can hold a maximal request head.
    pub fn readBufferLen(limits: Limits) usize {
        return limits.max_header_bytes + header_end.len;
    }
};

pub const Request = struct {
    method: []const u8,
    target: []const u8,
    /// Owned by the allocator passed to `readRequest` as `body_allocator`.
    body: []u8,
};

pub const ReadResult = union(enum) {
    request: Request,
    /// The request was malformed or exceeded a limit; reply with this status.
    reject: Status,
    /// The peer went away (or timed out) before sending a full request.
    closed,
};

pub const Response = struct {
    status: Status,
    content_type: ?[]const u8 = null,
    /// Value of the `Allow` header, for 405 responses.
    allow: ?[]const u8 = null,
    body: []const u8 = "",

    pub fn empty(status: Status) Response {
        return .{ .status = status };
    }

    pub fn text(status: Status, body: []const u8) Response {
        return .{ .status = status, .content_type = "text/plain; charset=utf-8", .body = body };
    }
};

const crlf = "\r\n";
const header_end = "\r\n\r\n";

/// Reads one request from `reader`, whose buffer must be at least
/// `limits.readBufferLen()` bytes. Method and target are copied into `arena`;
/// the body is allocated with `body_allocator`.
pub fn readRequest(
    reader: *Io.Reader,
    arena: Allocator,
    body_allocator: Allocator,
    limits: Limits,
) Allocator.Error!ReadResult {
    std.debug.assert(reader.buffer.len >= limits.readBufferLen());

    var search_from: usize = 0;
    const head_len = while (true) {
        const buffered = reader.buffered();
        if (std.mem.indexOfPos(u8, buffered, search_from, header_end)) |end| break end;
        if (buffered.len > limits.max_header_bytes) return .{ .reject = .request_header_fields_too_large };
        search_from = buffered.len -| (header_end.len - 1);
        reader.fillMore() catch return .closed;
    };
    if (head_len > limits.max_header_bytes) return .{ .reject = .request_header_fields_too_large };

    const head = reader.buffered()[0..head_len];
    var lines = std.mem.splitSequence(u8, head, crlf);

    // request-line = method SP request-target SP HTTP-version
    const request_line = lines.first();
    const sp1 = std.mem.indexOfScalar(u8, request_line, ' ') orelse return .{ .reject = .bad_request };
    const sp2 = std.mem.indexOfScalarPos(u8, request_line, sp1 + 1, ' ') orelse return .{ .reject = .bad_request };
    if (sp1 == 0 or sp2 == sp1 + 1) return .{ .reject = .bad_request };
    const version = request_line[sp2 + 1 ..];
    if (!std.mem.startsWith(u8, version, "HTTP/1.")) {
        return .{ .reject = if (std.mem.startsWith(u8, version, "HTTP/")) .http_version_not_supported else .bad_request };
    }

    var content_length: ?usize = null;
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return .{ .reject = .bad_request };
        if (colon == 0) return .{ .reject = .bad_request };
        const name = line[0..colon];
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            const len = parseContentLength(value) orelse return .{ .reject = .bad_request };
            if (content_length) |prev| if (prev != len) return .{ .reject = .bad_request };
            content_length = len;
        } else if (std.ascii.eqlIgnoreCase(name, "Transfer-Encoding")) {
            return .{ .reject = .not_implemented };
        }
    }

    // Copy what we keep out of the reader buffer before reading the body,
    // which may rebase that buffer.
    const method = try arena.dupe(u8, request_line[0..sp1]);
    const target = try arena.dupe(u8, request_line[sp1 + 1 .. sp2]);
    reader.toss(head_len + header_end.len);

    const length = content_length orelse 0;
    if (length > limits.max_body_bytes) {
        // Consume the body so the peer sees a clean close rather than a reset.
        reader.discardAll(length) catch {};
        return .{ .reject = .payload_too_large };
    }

    const body = try body_allocator.alloc(u8, length);
    reader.readSliceAll(body) catch {
        // Truncated body: the peer is gone.
        body_allocator.free(body);
        return .closed;
    };

    return .{ .request = .{ .method = method, .target = target, .body = body } };
}

/// Parses a non-empty run of ASCII digits (no sign, no separators).
fn parseContentLength(value: []const u8) ?usize {
    if (value.len == 0) return null;
    for (value) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseUnsigned(usize, value, 10) catch null;
}

/// Writes the full response, always with `Connection: close`.
pub fn writeResponse(writer: *Io.Writer, response: Response) Io.Writer.Error!void {
    const status = response.status;
    try writer.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase() orelse "Unknown" });
    if (response.content_type) |value| try writer.print("Content-Type: {s}\r\n", .{value});
    if (response.allow) |value| try writer.print("Allow: {s}\r\n", .{value});
    if (status != .no_content) try writer.print("Content-Length: {d}\r\n", .{response.body.len});
    try writer.writeAll("Connection: close\r\n\r\n");
    try writer.writeAll(response.body);
    try writer.flush();
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// Reads `raw` through a reader whose buffer meets `readBufferLen`.
const TestRead = struct {
    buffer: []u8,
    reader: Io.Reader,
    arena: std.heap.ArenaAllocator,
    result: ReadResult,

    fn init(t: *TestRead, raw: []const u8) !void {
        const limits: Limits = .{};
        t.buffer = try testing.allocator.alloc(u8, limits.readBufferLen());
        @memcpy(t.buffer[0..raw.len], raw);
        t.reader = .fixed(t.buffer);
        t.reader.end = raw.len;
        t.arena = .init(testing.allocator);
        t.result = try readRequest(&t.reader, t.arena.allocator(), testing.allocator, limits);
    }

    fn deinit(t: *TestRead) void {
        if (t.result == .request) testing.allocator.free(t.result.request.body);
        t.arena.deinit();
        testing.allocator.free(t.buffer);
    }
};

fn expectResult(expected: ReadResult, raw: []const u8) !void {
    var t: TestRead = undefined;
    try t.init(raw);
    defer t.deinit();
    try testing.expectEqual(expected, t.result);
}

test "parses a request with a body" {
    var t: TestRead = undefined;
    try t.init("PUT /kv/a HTTP/1.1\r\ncontent-length:  5 \r\nHost: x\r\n\r\nhello");
    defer t.deinit();
    const req = t.result.request;
    try testing.expectEqualStrings("PUT", req.method);
    try testing.expectEqualStrings("/kv/a", req.target);
    try testing.expectEqualStrings("hello", req.body);
}

test "header limit" {
    const limits: Limits = .{};
    const raw = try testing.allocator.alloc(u8, limits.max_header_bytes + 1);
    defer testing.allocator.free(raw);
    @memset(raw, 'a');
    try expectResult(.{ .reject = .request_header_fields_too_large }, raw);
}

test "rejects malformed requests" {
    try expectResult(.{ .reject = .bad_request }, "GET /\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, " / HTTP/1.1\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, "GET  HTTP/1.1\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, "GET / FTP/1.1\r\n\r\n");
    try expectResult(.{ .reject = .http_version_not_supported }, "GET / HTTP/2\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, "GET / HTTP/1.1\r\nNoColon\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, "GET / HTTP/1.1\r\n: x\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, "GET / HTTP/1.1\r\nContent-Length: +1\r\n\r\nx");
    try expectResult(.{ .reject = .bad_request }, "GET / HTTP/1.1\r\nContent-Length: 1_0\r\n\r\nx");
    try expectResult(.{ .reject = .bad_request }, "GET / HTTP/1.1\r\nContent-Length:\r\n\r\n");
    try expectResult(.{ .reject = .bad_request }, "GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nxx");
    try expectResult(.{ .reject = .not_implemented }, "GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n");
    try expectResult(.{ .reject = .payload_too_large }, "PUT /kv/a HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n");
}

test "truncated input closes" {
    try expectResult(.closed, "GET / HTTP/1.1\r\n");
    try expectResult(.closed, "PUT /kv/a HTTP/1.1\r\nContent-Length: 4\r\n\r\nab");
}

test "writes responses" {
    var buf: [256]u8 = undefined;
    var writer: Io.Writer = .fixed(&buf);
    try writeResponse(&writer, .text(.ok, "ok"));
    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
        writer.buffered(),
    );

    writer = .fixed(&buf);
    try writeResponse(&writer, .empty(.no_content));
    try testing.expectEqualStrings("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n", writer.buffered());
}
