//! The HTTP server: accepts connections and serves each one concurrently,
//! handing every request to the router.

const Server = @This();

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;
const Store = @import("db/Store.zig");
const Context = @import("http/Context.zig");
const router = @import("router.zig");

const log = std.log.scoped(.server);

/// Bounds the size of a request head (request line and headers).
const recv_buffer_len = 16 * 1024;
const send_buffer_len = 16 * 1024;

gpa: Allocator,
io: Io,
store: *Store,

/// Listens on `address` and serves requests until the task is canceled.
pub fn serve(server: *Server, address: net.IpAddress) !void {
    const io = server.io;
    var listener = try address.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);
    log.info("listening on {f}", .{address});

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, handleConnection, .{ server, stream }) catch |err| {
            log.warn("cannot serve connection: {t}", .{err});
            stream.close(io);
        };
    }
}

fn handleConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    var recv_buffer: [recv_buffer_len]u8 = undefined;
    var send_buffer: [send_buffer_len]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var http_server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    var arena_state: std.heap.ArenaAllocator = .init(server.gpa);
    defer arena_state.deinit();

    while (true) {
        _ = arena_state.reset(.retain_capacity);
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            error.ReadFailed => return,
            else => {
                log.debug("bad request head: {t}", .{err});
                return;
            },
        };
        normalizeBodyFraming(&request.head);
        server.handleRequest(arena_state.allocator(), &request) catch |err| switch (err) {
            error.ReadFailed, error.WriteFailed => return,
        };
        if (http_server.reader.state != .ready) return;
    }
}

/// Makes the body framing of a request head explicit, so that
/// `std.http.Server` can read or skip the body:
///
/// - A request without `Content-Length` or `Transfer-Encoding` has no body
///   (RFC 9112, section 6.3); `std.http.Server` asserts that methods which
///   may carry a body declare one of the two.
/// - `std.http.Server` does not read bodies sent with other methods, such as
///   `GET` or `DELETE`, so the bytes would be parsed as the next request.
///   Such a connection is closed after the response instead.
fn normalizeBodyFraming(head: *http.Server.Request.Head) void {
    const framed = head.transfer_encoding != .none or head.content_length != null;
    if (head.method.requestHasBody()) {
        if (!framed) head.content_length = 0;
    } else if (head.transfer_encoding != .none or (head.content_length orelse 0) > 0) {
        head.keep_alive = false;
    }
}

test normalizeBodyFraming {
    var head: http.Server.Request.Head = undefined;
    head.method = .POST;
    head.transfer_encoding = .none;
    head.content_length = null;
    head.keep_alive = true;
    normalizeBodyFraming(&head);
    try std.testing.expectEqual(@as(?u64, 0), head.content_length);
    try std.testing.expect(head.keep_alive);

    head.method = .DELETE;
    head.content_length = 3;
    normalizeBodyFraming(&head);
    try std.testing.expect(!head.keep_alive);

    head.method = .GET;
    head.content_length = 0;
    head.keep_alive = true;
    normalizeBodyFraming(&head);
    try std.testing.expect(head.keep_alive);
}

/// Serves one request. Only connection failures are returned; all other
/// errors are answered with an error response.
fn handleRequest(server: *Server, arena: Allocator, request: *http.Server.Request) error{ ReadFailed, WriteFailed }!void {
    var ctx = Context.init(arena, server.store, request) catch {
        return request.respond("", .{ .status = .internal_server_error, .keep_alive = false }) catch error.WriteFailed;
    };
    router.dispatch(&ctx) catch |err| switch (err) {
        error.ReadFailed, error.WriteFailed => |e| return e,
        error.PayloadTooLarge => try sendFailure(&ctx, .payload_too_large, "request body too large"),
        error.HttpExpectationFailed => try sendFailure(&ctx, .expectation_failed, "unsupported expectation"),
        error.OutOfMemory, error.Sqlite => {
            log.err("{t} {s}: {t}", .{ ctx.method, ctx.path, err });
            try sendFailure(&ctx, .internal_server_error, "internal server error");
        },
    };
}

fn sendFailure(ctx: *Context, status: http.Status, message: []const u8) error{ ReadFailed, WriteFailed }!void {
    if (ctx.responded) return;
    ctx.sendError(status, message) catch |err| switch (err) {
        error.ReadFailed, error.WriteFailed => |e| return e,
        else => return error.WriteFailed,
    };
}
