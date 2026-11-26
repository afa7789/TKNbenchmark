//! HTTP connection handling and request dispatch for the kvhttp routes.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const routes = @import("routes.zig");

const log = std.log.scoped(.server);

/// Largest accepted value, in bytes.
pub const max_value_len = 1024 * 1024;

/// Upper bound on how much of an oversized body is drained before replying
/// 413, so the client sees the response instead of a connection reset.
const max_drain_len = 64 * 1024 * 1024;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
};

/// Serves HTTP/1.1 requests on `stream` until the client closes the
/// connection or asks for it to be closed. Always closes `stream`.
pub fn serveConnection(ctx: *const Context, stream: net.Stream) void {
    defer stream.close(ctx.io);

    var recv_buffer: [16 * 1024]u8 = undefined;
    var send_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(ctx.io, &recv_buffer);
    var stream_writer = stream.writer(ctx.io, &send_buffer);
    var server = http.Server.init(&stream_reader.interface, &stream_writer.interface);

    while (true) {
        const head_buffer = server.reader.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                log.debug("receiving request head failed: {t}", .{err});
                return;
            },
        };
        const head = http.Server.Request.Head.parse(head_buffer) catch |err| {
            respondUnparsed(&server, head_buffer, err) catch {};
            return;
        };
        var request: http.Server.Request = .{
            .server = &server,
            .head_buffer = head_buffer,
            .head = head,
        };
        const keep_alive = handleRequest(ctx, &request) catch |err| {
            log.debug("request failed: {t}", .{err});
            return;
        };
        if (!keep_alive) return;
    }
}

/// Handles one request. Returns whether the connection may be reused.
fn handleRequest(ctx: *const Context, request: *http.Server.Request) !bool {
    const reusable = isReusable(&request.head);
    const status: http.Status, const body: []const u8, const content_type: ?[]const u8 = switch (routes.match(request.head.target)) {
        .not_found => .{ .not_found, "", null },
        .invalid_key => .{ .bad_request, "", null },
        .health => switch (request.head.method) {
            .GET => .{ .ok, "ok", "text/plain" },
            else => .{ .method_not_allowed, "", null },
        },
        .list => switch (request.head.method) {
            .GET => {
                const json = try listJson(ctx);
                defer ctx.gpa.free(json);
                try respond(request, .ok, json, "application/json", reusable);
                return reusable;
            },
            else => .{ .method_not_allowed, "", null },
        },
        .item => |key| switch (request.head.method) {
            .GET => {
                const value = try ctx.store.fetch(ctx.io, ctx.gpa, key) orelse {
                    try respond(request, .not_found, "", null, reusable);
                    return reusable;
                };
                defer ctx.gpa.free(value);
                try respond(request, .ok, value, "application/octet-stream", reusable);
                return reusable;
            },
            .PUT => {
                // Reading the body invalidates `key`, which points into the head buffer.
                var key_buffer: [routes.max_key_len]u8 = undefined;
                const owned_key = key_buffer[0..key.len];
                @memcpy(owned_key, key);

                const value = readValue(ctx.store.gpa, request) catch |err| switch (err) {
                    error.ValueTooLarge => {
                        try respond(request, .payload_too_large, "", null, false);
                        return false;
                    },
                    else => return err,
                };
                const status: http.Status = switch (try ctx.store.put(ctx.io, owned_key, value)) {
                    .created => .created,
                    .replaced => .ok,
                };
                try respond(request, status, "", null, reusable);
                return reusable;
            },
            .DELETE => .{ if (try ctx.store.delete(ctx.io, key)) .no_content else .not_found, "", null },
            else => .{ .method_not_allowed, "", null },
        },
    };
    try respond(request, status, body, content_type, reusable);
    return reusable;
}

fn respond(
    request: *http.Server.Request,
    status: http.Status,
    body: []const u8,
    content_type: ?[]const u8,
    keep_alive: bool,
) !void {
    const header: []const http.Header = if (content_type) |ct| &.{.{ .name = "content-type", .value = ct }} else &.{};
    try request.respond(body, .{
        .status = status,
        .keep_alive = keep_alive,
        .extra_headers = header,
    });
}

/// A connection can only be reused if the request body framing is known, so
/// that any unread body can be skipped to find the next request.
fn isReusable(head: *const http.Server.Request.Head) bool {
    if (!head.keep_alive) return false;
    const framed = head.transfer_encoding != .none or head.content_length != null;
    if (head.method.requestHasBody()) return framed;
    // The std server does not skip bodies sent with GET, DELETE, etc.
    return head.transfer_encoding == .none and (head.content_length orelse 0) == 0;
}

/// Reads the request body into memory allocated with `gpa`.
fn readValue(gpa: Allocator, request: *http.Server.Request) ![]u8 {
    const head = &request.head;
    if (head.transfer_encoding == .none and head.content_length == null) {
        // Without framing the body would extend to EOF; treat it as empty.
        return gpa.alloc(u8, 0);
    }
    const content_length = head.content_length;
    var transfer_buffer: [4096]u8 = undefined;
    const body = try request.readerExpectContinue(&transfer_buffer);
    if (content_length) |len| if (len > max_value_len) {
        drain(body);
        return error.ValueTooLarge;
    };
    return body.allocRemaining(gpa, .limited(max_value_len + 1)) catch |err| switch (err) {
        error.StreamTooLong => {
            drain(body);
            return error.ValueTooLarge;
        },
        else => return err,
    };
}

fn drain(body: *Io.Reader) void {
    _ = body.discard(.limited(max_drain_len)) catch {};
}

/// Encodes the store's keys as a JSON array. Keys are restricted to
/// `[A-Za-z0-9_-]`, so they never need escaping.
fn listJson(ctx: *const Context) ![]u8 {
    var list = try ctx.store.listKeys(ctx.io, ctx.gpa);
    defer list.deinit(ctx.gpa);

    var out: Io.Writer.Allocating = .init(ctx.gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeByte('[');
    for (list.keys, 0..) |key, i| {
        if (i != 0) try w.writeByte(',');
        try w.print("\"{s}\"", .{key});
    }
    try w.writeByte(']');
    return out.toOwnedSlice();
}

/// Replies to a request whose head the std parser rejected. An unknown method
/// on a known route is still a 405, as the routing rules require.
fn respondUnparsed(server: *http.Server, head_buffer: []const u8, err: anyerror) !void {
    const status: http.Status = status: {
        if (err != error.UnknownHttpMethod) break :status .bad_request;
        const line_end = std.mem.indexOf(u8, head_buffer, "\r\n") orelse head_buffer.len;
        var parts = std.mem.tokenizeScalar(u8, head_buffer[0..line_end], ' ');
        _ = parts.next();
        const target = parts.next() orelse break :status .bad_request;
        break :status switch (routes.match(target)) {
            .not_found => .not_found,
            .invalid_key => .bad_request,
            .health, .list, .item => .method_not_allowed,
        };
    };
    try server.out.print("HTTP/1.1 {d} {s}\r\ncontent-length: 0\r\nconnection: close\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try server.out.flush();
}
