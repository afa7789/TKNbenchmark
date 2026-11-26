//! Serves a single HTTP/1.1 request on an accepted connection, then closes it.

const Connection = @This();

const std = @import("std");
const Io = std.Io;
const http = std.http;
const net = Io.net;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const route = @import("route.zig");

const log = std.log.scoped(.connection);

/// Largest accepted value, in bytes.
pub const max_value_len = 1 << 20;
/// Largest accepted request head, in bytes.
const max_head_len = 16 * 1024;

const text_plain: http.Header = .{ .name = "content-type", .value = "text/plain; charset=utf-8" };
const application_json: http.Header = .{ .name = "content-type", .value = "application/json" };

store: *Store,
io: Io,
gpa: Allocator,

/// Entry point for a connection task. Never fails: errors only affect this
/// connection and are logged.
pub fn handle(store: *Store, io: Io, gpa: Allocator, stream: net.Stream) void {
    defer stream.close(io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [8 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    const c: Connection = .{ .store = store, .io = io, .gpa = gpa };
    c.serve(&server) catch |err| switch (err) {
        error.ReadFailed => log.debug("read failed: {t}", .{stream_reader.err orelse err}),
        error.WriteFailed => log.debug("write failed: {t}", .{stream_writer.err orelse err}),
        else => log.debug("connection dropped: {t}", .{err}),
    };
}

const ServeError = error{
    ReadFailed,
    WriteFailed,
    EndOfStream,
    HttpRequestTruncated,
    HttpExpectationFailed,
} || Io.Cancelable;

fn serve(c: Connection, server: *http.Server) ServeError!void {
    const head_bytes = server.reader.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        error.HttpHeadersOversize => return respondBare(server.out, .request_header_fields_too_large),
        error.HttpRequestTruncated, error.ReadFailed => |e| return e,
    };
    const head = http.Server.Request.Head.parse(head_bytes) catch |err| switch (err) {
        // std.http only knows the standard methods; any other token is still
        // a valid request, just one no route supports.
        error.UnknownHttpMethod => return respondBare(server.out, unknownMethodStatus(head_bytes)),
        else => return respondBare(server.out, .bad_request),
    };
    var request: http.Server.Request = .{ .server = server, .head = head, .head_buffer = head_bytes };

    c.dispatch(&request) catch |err| switch (err) {
        error.OutOfMemory => {
            log.warn("out of memory serving a {t} request", .{head.method});
            return respond(&request, .internal_server_error, "", null);
        },
        else => |e| return e,
    };
}

fn dispatch(c: Connection, request: *http.Server.Request) (ServeError || Allocator.Error)!void {
    switch (route.resolve(request.head.method, request.head.target)) {
        .health => try respond(request, .ok, "ok", text_plain),
        .list_keys => {
            const json = try c.store.keysJson(c.io, c.gpa);
            defer c.gpa.free(json);
            try respond(request, .ok, json, application_json);
        },
        .get_value => |key| {
            const value = try c.store.get(c.io, c.gpa, key) orelse
                return respond(request, .not_found, "", null);
            defer c.gpa.free(value);
            try respond(request, .ok, value, null);
        },
        .put_value => |key| try c.put(request, key),
        .delete_value => |key| {
            const removed = try c.store.remove(c.io, key);
            try respond(request, if (removed) .no_content else .not_found, "", null);
        },
        .status => |status| try respond(request, status, "", null),
    }
}

fn put(c: Connection, request: *http.Server.Request, key_in_head: []const u8) (ServeError || Allocator.Error)!void {
    // Reading the body may overwrite the head buffer the key points into.
    var key_buffer: [route.max_key_len]u8 = undefined;
    const key = key_buffer[0..key_in_head.len];
    @memcpy(key, key_in_head);

    const value = readValue(request, c.gpa) catch |err| switch (err) {
        error.ValueTooLarge => return respondStatusOnly(request, .payload_too_large),
        else => |e| return e,
    };
    const result = c.store.put(c.io, key, value) catch |err| {
        c.gpa.free(value);
        return err;
    };
    try respondStatusOnly(request, switch (result) {
        .created => .created,
        .replaced => .ok,
    });
}

/// Reads the request body into memory allocated with `gpa`.
fn readValue(request: *http.Server.Request, gpa: Allocator) (ServeError || Allocator.Error || error{ValueTooLarge})![]u8 {
    const head = request.head;
    // A request with neither Content-Length nor Transfer-Encoding has no body.
    if (head.transfer_encoding == .none and head.content_length == null) return gpa.alloc(u8, 0);
    if (head.content_length) |len| if (len > max_value_len) return error.ValueTooLarge;

    var transfer_buffer: [4096]u8 = undefined;
    const body = try request.readerExpectContinue(&transfer_buffer);
    if (head.content_length) |len| {
        const value = try gpa.alloc(u8, @intCast(len));
        errdefer gpa.free(value);
        try body.readSliceAll(value);
        return value;
    }
    return body.allocRemaining(gpa, .limited(max_value_len + 1)) catch |err| switch (err) {
        error.StreamTooLong => error.ValueTooLarge,
        else => |e| e,
    };
}

/// Responds to a request whose body has already been consumed or must not be.
fn respondStatusOnly(request: *http.Server.Request, status: http.Status) ServeError!void {
    try request.respond("", .{
        .status = status,
        .keep_alive = false,
        .transfer_encoding = if (status == .no_content) .none else null,
    });
}

/// Drains any request body, then sends a complete response and closes the
/// connection. Draining first avoids the kernel resetting the connection
/// because of unread input when the socket is closed.
fn respond(
    request: *http.Server.Request,
    status: http.Status,
    content: []const u8,
    content_type: ?http.Header,
) ServeError!void {
    try discardBody(request);
    try request.respond(content, .{
        .status = status,
        .keep_alive = false,
        // A 204 response must not carry Content-Length; the connection close
        // delimits it instead.
        .transfer_encoding = if (status == .no_content) .none else null,
        .extra_headers = if (content_type) |h| &.{h} else &.{},
    });
}

/// Discards a request body that the route does not use. Bodies larger than
/// any value we accept are left unread; the connection closes either way.
fn discardBody(request: *http.Server.Request) ServeError!void {
    const head = &request.head;
    // The client waits for "100 Continue" before sending; it never will be.
    if (head.expect != null) return;
    const len = head.content_length orelse return;
    if (len == 0 or len > max_value_len) return;
    try request.server.reader.in.discardAll(@intCast(len));
    // Header strings may have been overwritten by the discarded bytes.
    head.content_type = null;
}

/// Response for a request line whose method `std.http` does not recognise.
fn unknownMethodStatus(head_bytes: []const u8) http.Status {
    const line_end = std.mem.find(u8, head_bytes, "\r\n") orelse head_bytes.len;
    var it = std.mem.tokenizeScalar(u8, head_bytes[0..line_end], ' ');
    _ = it.next(); // method
    const target = it.next() orelse return .bad_request;
    return switch (route.resolve(null, target)) {
        .status => |status| status,
        else => unreachable, // every route requires a known method
    };
}

/// Writes a minimal response when no parsed `Request` is available.
fn respondBare(out: *Io.Writer, status: http.Status) ServeError!void {
    try out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-length: 0\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try out.flush();
}

test unknownMethodStatus {
    const testing = std.testing;
    try testing.expectEqual(http.Status.method_not_allowed, unknownMethodStatus("FOO /health HTTP/1.1\r\n\r\n"));
    try testing.expectEqual(http.Status.method_not_allowed, unknownMethodStatus("FOO /kv/a HTTP/1.1\r\n\r\n"));
    try testing.expectEqual(http.Status.bad_request, unknownMethodStatus("FOO /kv/a.b HTTP/1.1\r\n\r\n"));
    try testing.expectEqual(http.Status.not_found, unknownMethodStatus("FOO /x HTTP/1.1\r\n\r\n"));
    try testing.expectEqual(http.Status.bad_request, unknownMethodStatus("FOO\r\n\r\n"));
}
