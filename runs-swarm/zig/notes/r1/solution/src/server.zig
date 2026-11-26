//! HTTP/1.1 transport: accepts connections, serves each one in its own
//! concurrent task, and translates between `std.http.Server` and the
//! `api.Request`/`api.Response` types the router works with.

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const api = @import("api.zig");
const router = @import("router.zig");
const Pool = @import("db/Pool.zig");

const log = std.log.scoped(.server);

pub const Options = struct {
    /// Larger request bodies are rejected with 413.
    max_body_len: usize = 1 << 20,
    /// Per-connection receive buffer; it must hold the whole request head.
    recv_buffer_len: usize = 16 * 1024,
    send_buffer_len: usize = 16 * 1024,
};

pub const Server = struct {
    io: Io,
    /// Thread-safe allocator for per-connection memory.
    gpa: Allocator,
    pool: *Pool,
    options: Options = .{},

    /// Accepts connections until canceled, serving each concurrently.
    pub fn serve(server: *const Server, listener: *net.Server) Io.Cancelable!void {
        const io = server.io;
        var connections: Io.Group = .init;
        defer connections.cancel(io);

        while (true) {
            const stream = listener.accept(io) catch |err| switch (err) {
                error.Canceled => |e| return e,
                error.ConnectionAborted => continue,
                else => |e| {
                    // Typically running out of file descriptors: back off
                    // instead of spinning, then keep serving.
                    log.err("accept failed: {t}", .{e});
                    try io.sleep(.fromMilliseconds(100), .awake);
                    continue;
                },
            };
            connections.concurrent(io, serveConnection, .{ server, stream }) catch |err| {
                log.err("cannot serve connection: {t}", .{err});
                stream.close(io);
            };
        }
    }

    fn serveConnection(server: *const Server, stream: net.Stream) void {
        const io = server.io;
        defer stream.close(io);

        const buffers = server.gpa.alloc(u8, server.options.recv_buffer_len + server.options.send_buffer_len) catch {
            log.err("out of memory accepting a connection", .{});
            return;
        };
        defer server.gpa.free(buffers);

        var stream_reader = stream.reader(io, buffers[0..server.options.recv_buffer_len]);
        var stream_writer = stream.writer(io, buffers[server.options.recv_buffer_len..]);
        var http_server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

        var arena_state: std.heap.ArenaAllocator = .init(server.gpa);
        defer arena_state.deinit();

        while (true) {
            // Keep a little memory around between requests on a connection.
            _ = arena_state.reset(.{ .retain_with_limit = 64 * 1024 });

            var request = http_server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                error.HttpHeadersOversize => return rejectHead(&stream_writer.interface, .request_header_fields_too_large),
                error.HttpHeadersInvalid => return rejectHead(&stream_writer.interface, .bad_request),
                error.HttpRequestTruncated, error.ReadFailed => return,
            };
            const keep_alive = server.serveRequest(&request, arena_state.allocator()) catch |err| {
                log.debug("connection dropped: {t}", .{err});
                return;
            };
            if (!keep_alive) return;
        }
    }

    /// Reads the request body, dispatches the request and sends the response.
    /// Returns whether the connection can serve another request.
    fn serveRequest(server: *const Server, request: *http.Server.Request, arena: Allocator) !bool {
        const head = request.head;
        // Reading the body invalidates the strings in `request.head`.
        const target = try arena.dupe(u8, head.target);
        var keep_alive = head.keep_alive;

        const body: []const u8 = body: {
            const chunked = head.transfer_encoding == .chunked;
            if (!head.method.requestHasBody()) {
                // The body of e.g. a DELETE is not read, so the stream cannot
                // be reused for another request.
                if (chunked or (head.content_length orelse 0) > 0) keep_alive = false;
                break :body "";
            }
            if (head.transfer_compression != .identity) {
                return respondError(request, arena, .unsupported_media_type, "compressed request bodies are not supported", false);
            }
            if (!chunked and head.content_length == null) {
                // No framing: the request has no body (RFC 9112, 6.3).
                keep_alive = false;
                break :body "";
            }
            if ((head.content_length orelse 0) > server.options.max_body_len) {
                return respondError(request, arena, .payload_too_large, "request body is too large", false);
            }
            const reader = request.readerExpectContinue(&.{}) catch return error.WriteFailed;
            break :body reader.allocRemaining(arena, .limited(server.options.max_body_len)) catch |err| switch (err) {
                error.StreamTooLong => return respondError(request, arena, .payload_too_large, "request body is too large", false),
                error.OutOfMemory, error.ReadFailed => |e| return e,
            };
        };

        const ctx: api.Context = .{ .io = server.io, .arena = arena, .pool = server.pool };
        const response = router.dispatch(&ctx, .init(head.method, target, body)) catch |err| {
            if (err == error.Canceled) return err;
            log.err("{t} {s} failed: {t}", .{ head.method, target, err });
            return respondError(request, arena, .internal_server_error, "internal server error", keep_alive);
        };
        try respond(request, response, keep_alive);
        return keep_alive;
    }
};

fn respond(request: *http.Server.Request, response: api.Response, keep_alive: bool) !void {
    var headers_buf: [2]http.Header = undefined;
    var headers: std.ArrayList(http.Header) = .initBuffer(&headers_buf);
    if (response.content_type.header()) |value| headers.appendAssumeCapacity(.{ .name = "content-type", .value = value });
    if (response.allow) |value| headers.appendAssumeCapacity(.{ .name = "allow", .value = value });

    request.respond(response.body, .{
        .status = response.status,
        .keep_alive = keep_alive,
        .extra_headers = headers.items,
    }) catch return error.WriteFailed;
}

/// Sends a JSON error response; returns whether the connection stays open.
fn respondError(
    request: *http.Server.Request,
    arena: Allocator,
    status: http.Status,
    message: []const u8,
    keep_alive: bool,
) !bool {
    try respond(request, try .err(arena, status, message), keep_alive);
    return keep_alive;
}

/// Answers a request whose head could not be parsed, then gives up on the
/// connection.
fn rejectHead(out: *Io.Writer, status: http.Status) void {
    out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-length: 0\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    }) catch return;
    out.flush() catch return;
}
