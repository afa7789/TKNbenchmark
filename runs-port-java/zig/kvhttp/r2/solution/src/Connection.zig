//! Serves a single HTTP/1.1 request on an accepted connection, then closes it.

const std = @import("std");
const Io = std.Io;
const http = std.http;
const Allocator = std.mem.Allocator;

const route = @import("route.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.connection);

/// Largest accepted value; bigger request bodies are answered with 413.
pub const max_value_len = 1 << 20;
/// The whole request head must fit in the receive buffer.
const max_head_len = 16 * 1024;
/// Unread request body bytes we are willing to consume so that closing the
/// socket does not reset the connection before the client reads the response.
const max_drain_len = 8 * max_value_len;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
};

/// Handles the request on `stream` and closes it. Never fails: errors only
/// affect this one connection.
pub fn serve(ctx: *const Context, stream: Io.net.Stream) void {
    defer stream.close(ctx.io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [8 * 1024]u8 = undefined;
    var stream_reader = stream.reader(ctx.io, &recv_buffer);
    var stream_writer = stream.writer(ctx.io, &send_buffer);

    handle(ctx, &stream_reader.interface, &stream_writer.interface) catch |err| switch (err) {
        error.ReadFailed => log.debug("read failed: {?t}", .{stream_reader.err}),
        error.WriteFailed => log.debug("write failed: {?t}", .{stream_writer.err}),
        else => log.debug("request failed: {t}", .{err}),
    };
}

const Response = struct {
    status: http.Status,
    content_type: ?[]const u8 = null,
    body: []const u8 = "",

    fn empty(status: http.Status) Response {
        return .{ .status = status };
    }

    fn write(r: Response, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(r.status), r.status.phrase() orelse "" });
        if (r.content_type) |content_type| try w.print("Content-Type: {s}\r\n", .{content_type});
        // RFC 9110 forbids Content-Length on 204 responses.
        if (r.status != .no_content) try w.print("Content-Length: {d}\r\n", .{r.body.len});
        try w.writeAll("Connection: close\r\n\r\n");
        try w.writeAll(r.body);
        try w.flush();
    }
};

fn handle(ctx: *const Context, in: *Io.Reader, out: *Io.Writer) !void {
    var http_reader: http.Reader = .{
        .in = in,
        .state = .ready,
        .interface = undefined,
        .max_head_len = in.buffer.len,
    };
    const head_bytes = http_reader.receiveHead() catch |err| switch (err) {
        error.HttpHeadersOversize => return Response.empty(.request_header_fields_too_large).write(out),
        error.HttpConnectionClosing, error.HttpRequestTruncated => return,
        error.ReadFailed => return error.ReadFailed,
    };
    const head = Head.parse(head_bytes) catch |err| return Response.empty(switch (err) {
        error.UnsupportedTransferEncoding => .not_implemented,
        error.InvalidRequest => .bad_request,
    }).write(out);

    // The head's memory is invalidated once the body is read, so the key is
    // copied out first.
    var key_buffer: [route.max_key_len]u8 = undefined;
    const op = copyKey(route.resolve(head.method, head.target), &key_buffer);

    const body: ?*Io.Reader = if (head.hasBody())
        http_reader.bodyReader(&.{}, head.transfer_encoding, head.content_length)
    else
        null;

    var arena_state: std.heap.ArenaAllocator = .init(ctx.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const response = try execute(ctx, arena, op, head.content_length, body);

    // Consume whatever body is left so the client sees an orderly close.
    if (body) |r| _ = r.discardShort(max_drain_len) catch {};

    try response.write(out);
}

fn execute(
    ctx: *const Context,
    arena: Allocator,
    op: route.Route,
    content_length: ?u64,
    body: ?*Io.Reader,
) !Response {
    const io = ctx.io;
    switch (op) {
        .health => return .{ .status = .ok, .content_type = "text/plain; charset=utf-8", .body = "ok" },
        .list_keys => {
            var json: Io.Writer.Allocating = .init(arena);
            ctx.store.writeKeysJson(io, arena, &json.writer) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                else => |e| return e,
            };
            return .{ .status = .ok, .content_type = "application/json", .body = json.written() };
        },
        .get => |key| {
            const value = try ctx.store.get(io, arena, key) orelse return .empty(.not_found);
            return .{ .status = .ok, .content_type = "application/octet-stream", .body = value };
        },
        .put => |key| {
            if (content_length) |len| if (len > max_value_len) return .empty(.payload_too_large);
            const value: []u8 = if (body) |r|
                r.allocRemaining(ctx.gpa, .limited(max_value_len + 1)) catch |err| switch (err) {
                    error.StreamTooLong => return .empty(.payload_too_large),
                    else => |e| return e,
                }
            else
                try ctx.gpa.alloc(u8, 0);
            return switch (try ctx.store.put(io, key, value)) {
                .created => .empty(.created),
                .replaced => .empty(.ok),
            };
        },
        .delete => |key| return .empty(if (try ctx.store.delete(io, key)) .no_content else .not_found),
        .reject => |status| return .empty(status),
    }
}

fn copyKey(op: route.Route, buffer: *[route.max_key_len]u8) route.Route {
    return switch (op) {
        inline .get, .put, .delete => |key, tag| blk: {
            @memcpy(buffer[0..key.len], key);
            break :blk @unionInit(route.Route, @tagName(tag), buffer[0..key.len]);
        },
        else => op,
    };
}

/// The parts of a request head this server cares about. Strings point into
/// the receive buffer.
const Head = struct {
    method: []const u8,
    target: []const u8,
    content_length: ?u64 = null,
    transfer_encoding: http.TransferEncoding = .none,

    const ParseError = error{ InvalidRequest, UnsupportedTransferEncoding };

    fn hasBody(h: Head) bool {
        return h.transfer_encoding == .chunked or (h.content_length orelse 0) > 0;
    }

    /// Accepts any method token so that unknown methods can be answered
    /// with 405 rather than rejected outright.
    fn parse(bytes: []const u8) ParseError!Head {
        var lines = std.mem.splitScalar(u8, bytes, '\n');

        const request_line = trimCr(lines.first());
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.first();
        const target = parts.next() orelse return error.InvalidRequest;
        const version = parts.next() orelse return error.InvalidRequest;
        if (parts.next() != null) return error.InvalidRequest;
        if (method.len == 0 or target.len == 0) return error.InvalidRequest;
        if (!std.mem.startsWith(u8, version, "HTTP/1.")) return error.InvalidRequest;

        var head: Head = .{ .method = method, .target = target };
        while (lines.next()) |raw_line| {
            const line = trimCr(raw_line);
            if (line.len == 0) break;
            const colon = std.mem.findScalar(u8, line, ':') orelse return error.InvalidRequest;
            const name = line[0..colon];
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                if (head.content_length != null) return error.InvalidRequest;
                head.content_length = std.fmt.parseInt(u64, value, 10) catch return error.InvalidRequest;
            } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                if (!std.ascii.eqlIgnoreCase(value, "chunked")) return error.UnsupportedTransferEncoding;
                head.transfer_encoding = .chunked;
            }
        }
        // RFC 9112 §6.1: a request with both framings is invalid.
        if (head.transfer_encoding == .chunked and head.content_length != null) return error.InvalidRequest;
        return head;
    }

    fn trimCr(line: []const u8) []const u8 {
        return std.mem.trimEnd(u8, line, "\r");
    }
};

const testing = std.testing;

test "Head.parse reads method, target and framing" {
    const head = try Head.parse("PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\nConnection: close\r\n\r\n");
    try testing.expectEqualStrings("PUT", head.method);
    try testing.expectEqualStrings("/kv/a", head.target);
    try testing.expectEqual(5, head.content_length.?);
    try testing.expect(head.hasBody());
}

test "Head.parse accepts unknown methods and chunked bodies" {
    const head = try Head.parse("BREW /pot HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n");
    try testing.expectEqualStrings("BREW", head.method);
    try testing.expectEqual(.chunked, head.transfer_encoding);
}

test "Head.parse rejects malformed heads" {
    try testing.expectError(error.InvalidRequest, Head.parse("GET /\r\n\r\n"));
    try testing.expectError(error.InvalidRequest, Head.parse("GET / HTTP/1.1\r\nContent-Length: x\r\n\r\n"));
    try testing.expectError(error.InvalidRequest, Head.parse("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n"));
    try testing.expectError(error.UnsupportedTransferEncoding, Head.parse("GET / HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"));
}
