//! Accepts connections and serves one request per connection, each on its
//! own concurrent task.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const http = @import("http.zig");
const router = @import("router.zig");

const Server = @This();

const log = std.log.scoped(.kvhttp);

pub const max_value_len = 1 << 20;

/// Must hold the entire request head.
const recv_buffer_len = 16 * 1024;
const send_buffer_len = 16 * 1024;
/// After responding early (e.g. 413), at most this many unread request-body
/// bytes are discarded so that closing the socket does not reset the
/// connection before the client has read the response.
const max_drain_len = 4 * max_value_len;

io: Io,
gpa: Allocator,
store: *Store,

/// Accepts connections until canceled.
pub fn run(server: *Server, listener: *net.Server) Io.Cancelable!void {
    const io = server.io;
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.ConnectionAborted => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                // Typically descriptor exhaustion; back off instead of spinning.
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
        };
        group.concurrent(io, serveConnection, .{ server, stream }) catch {
            // No spare concurrency: serve inline rather than drop the client.
            server.serveConnection(stream);
        };
    }
}

fn serveConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    var recv_buffer: [recv_buffer_len]u8 = undefined;
    var send_buffer: [send_buffer_len]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    const r = &stream_reader.interface;

    var unread_body: u64 = 0;
    server.handleRequest(r, &stream_writer.interface, &unread_body) catch |err| switch (err) {
        // The peer went away or the socket failed; nothing more can be sent.
        error.ReadFailed, error.WriteFailed, error.EndOfStream, error.Canceled => return,
    };

    if (unread_body > 0) {
        stream.shutdown(io, .send) catch return;
        r.discardAll64(@min(unread_body, max_drain_len)) catch {};
    }
}

const HandleError = Io.Reader.Error || Io.Writer.Error || Io.Cancelable;

/// Reads one request from `r` and writes the response to `w`. On return,
/// `unread_body` holds the number of declared request-body bytes not consumed.
fn handleRequest(server: *Server, r: *Io.Reader, w: *Io.Writer, unread_body: *u64) HandleError!void {
    const head_bytes = http.receiveHead(r) catch |err| switch (err) {
        error.HeadTooLarge => return http.writeResponse(w, .{ .status = .request_header_fields_too_large }),
        else => |e| return e,
    };
    const head = http.Head.parse(head_bytes) catch |err| return http.writeResponse(w, .{ .status = switch (err) {
        error.BadRequest => .bad_request,
        error.VersionNotSupported => .http_version_not_supported,
        error.ExpectationFailed => .expectation_failed,
    } });
    unread_body.* = head.content_length orelse 0;

    var body_buffer: ?[]u8 = null;
    defer if (body_buffer) |buffer| server.gpa.free(buffer);

    const response = server.respond(r, w, head, unread_body, &body_buffer) catch |err| switch (err) {
        error.OutOfMemory => blk: {
            log.err("out of memory serving {s} {s}", .{ head.method, head.target });
            break :blk http.Response{ .status = .internal_server_error };
        },
        else => |e| return e,
    };
    try http.writeResponse(w, response);
}

/// Executes the routed request. Response bodies that need freeing are
/// returned through `body_buffer`, allocated with `gpa`.
fn respond(
    server: *Server,
    r: *Io.Reader,
    w: *Io.Writer,
    head: http.Head,
    unread_body: *u64,
    body_buffer: *?[]u8,
) (HandleError || Allocator.Error)!http.Response {
    const io = server.io;
    const store = server.store;

    switch (router.resolve(head.method, head.target)) {
        .health => return .{ .status = .ok, .content_type = "text/plain; charset=utf-8", .body = "ok" },
        .list_keys => {
            const json = try store.keysJson(io, server.gpa);
            body_buffer.* = json;
            return .{ .status = .ok, .content_type = "application/json", .body = json };
        },
        .get => |key| {
            const value = try store.get(io, server.gpa, key) orelse return .{ .status = .not_found };
            body_buffer.* = value;
            return .{ .status = .ok, .content_type = "application/octet-stream", .body = value };
        },
        .delete => |key| return .{ .status = if (try store.delete(io, key)) .no_content else .not_found },
        .put => |key_in_head| {
            if (head.has_transfer_encoding) return .{ .status = .length_required };
            const len = head.content_length orelse 0;
            if (len > max_value_len) return .{ .status = .payload_too_large };

            // `key_in_head` points into the reader's buffer, which reading the body may overwrite.
            var key_storage: [router.max_key_len]u8 = undefined;
            const key = key_storage[0..key_in_head.len];
            @memcpy(key, key_in_head);

            if (head.expect_continue) try http.writeContinue(w);

            const value = try server.gpa.alloc(u8, @intCast(len));
            errdefer server.gpa.free(value);
            try r.readSliceAll(value);
            unread_body.* = 0;

            return .{ .status = switch (try store.put(io, key, value)) {
                .created => .created,
                .replaced => .ok,
            } };
        },
        .status => |status| return .{ .status = status },
    }
}
