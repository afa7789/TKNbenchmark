//! HTTP front end for the key-value store: connection handling, routing and
//! request bodies.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;
const Request = http.Server.Request;

const Store = @import("Store.zig");

const log = std.log.scoped(.server);

pub const max_value_bytes = 1024 * 1024;
pub const max_key_len = 64;

/// Upper bound on request body bytes read and thrown away (unused bodies and
/// oversized values) so the client sees our response instead of a reset.
const max_drain_bytes = 16 * 1024 * 1024;

const recv_buffer_len = 16 * 1024;
const send_buffer_len = 16 * 1024;

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
};

/// Accepts connections forever, serving each one concurrently.
pub fn serve(ctx: Context, listener: *net.Server) Io.Cancelable!void {
    const io = ctx.io;
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.ConnectionAborted, error.BlockedByFirewall, error.ProtocolFailure, error.WouldBlock => continue,
            else => {
                log.err("accept failed: {t}", .{err});
                // Typically fd exhaustion; back off instead of spinning.
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
        };
        group.concurrent(io, serveConnection, .{ ctx, stream }) catch |err| {
            log.err("cannot serve connection: {t}", .{err});
            stream.close(io);
        };
    }
}

fn serveConnection(ctx: Context, stream: net.Stream) Io.Cancelable!void {
    const io = ctx.io;
    defer stream.close(io);

    var recv_buffer: [recv_buffer_len]u8 = undefined;
    var send_buffer: [send_buffer_len]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing, error.HttpRequestTruncated => return,
            error.ReadFailed => return readFailure(&stream_reader),
            error.HttpHeadersOversize => return rejectHead(&stream_writer.interface, .request_header_fields_too_large),
            error.HttpHeadersInvalid => return rejectHead(&stream_writer.interface, .bad_request),
        };
        handleRequest(ctx, &request) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.ReadFailed => return readFailure(&stream_reader),
            error.HttpExpectationFailed => return rejectHead(&stream_writer.interface, .expectation_failed),
            error.EndOfStream, error.WriteFailed => return,
        };
        if (server.reader.state != .ready) return;
    }
}

/// The connection is unusable after a read error; only cancelation is worth
/// propagating.
fn readFailure(stream_reader: *const net.Stream.Reader) Io.Cancelable!void {
    if (stream_reader.err) |err| if (err == error.Canceled) return error.Canceled;
}

/// Answers a request whose head could not be parsed, then gives up on the
/// connection.
fn rejectHead(out: *Io.Writer, status: http.Status) void {
    out.print("HTTP/1.1 {d} {s}\r\ncontent-length: 0\r\nconnection: close\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    }) catch return;
    out.flush() catch return;
}

pub const Route = union(enum) {
    health,
    list,
    /// `/kv/<key>` with a syntactically valid key.
    item: []const u8,
    /// `/kv/<rest>` where `<rest>` is not a valid key.
    invalid_key,
    not_found,
};

pub fn resolveRoute(target: []const u8) Route {
    const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];
    if (std.mem.eql(u8, path, "/health")) return .health;
    if (std.mem.eql(u8, path, "/kv")) return .list;
    if (std.mem.startsWith(u8, path, "/kv/")) {
        const key = path["/kv/".len..];
        return if (isValidKey(key)) .{ .item = key } else .invalid_key;
    }
    return .not_found;
}

/// Matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

const HandleError = Io.Cancelable || Request.ExpectContinueError || error{
    ReadFailed,
    /// The client hung up in the middle of the request body.
    EndOfStream,
};

fn handleRequest(ctx: Context, request: *Request) HandleError!void {
    const method = request.head.method;
    switch (resolveRoute(request.head.target)) {
        .health => {
            if (method != .GET) return methodNotAllowed(request, "GET");
            return respond(request, .ok, "ok", "text/plain; charset=utf-8");
        },
        .list => {
            if (method != .GET) return methodNotAllowed(request, "GET");
            var json: Io.Writer.Allocating = .init(ctx.gpa);
            defer json.deinit();
            ctx.store.writeKeysJson(ctx.io, ctx.gpa, &json.writer) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.OutOfMemory, error.WriteFailed => return internalError(request),
            };
            return respond(request, .ok, json.written(), "application/json");
        },
        .item => |key_slice| {
            // The head buffer may be overwritten once the body is read.
            var key_buffer: [max_key_len]u8 = undefined;
            const key = key_buffer[0..key_slice.len];
            @memcpy(key, key_slice);
            switch (method) {
                .GET => return getValue(ctx, request, key),
                .PUT => return putValue(ctx, request, key),
                .DELETE => {
                    const removed = try ctx.store.remove(ctx.io, key);
                    return respond(request, if (removed) .no_content else .not_found, "", null);
                },
                else => return methodNotAllowed(request, "GET, PUT, DELETE"),
            }
        },
        .invalid_key => return respond(request, .bad_request, "", null),
        .not_found => return respond(request, .not_found, "", null),
    }
}

fn getValue(ctx: Context, request: *Request, key: []const u8) HandleError!void {
    const value = ctx.store.get(ctx.io, ctx.gpa, key) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.OutOfMemory => return internalError(request),
    } orelse return respond(request, .not_found, "", null);
    defer ctx.gpa.free(value);
    return respond(request, .ok, value, "application/octet-stream");
}

fn putValue(ctx: Context, request: *Request, key: []const u8) HandleError!void {
    const value = readValue(ctx.gpa, request) catch |err| switch (err) {
        error.ValueTooLarge => return respondClose(request, .payload_too_large),
        error.OutOfMemory => return respondClose(request, .internal_server_error),
        error.ReadFailed, error.EndOfStream, error.WriteFailed, error.HttpExpectationFailed => |e| return e,
    };
    const result = ctx.store.put(ctx.io, key, value) catch |err| {
        ctx.gpa.free(value);
        switch (err) {
            error.Canceled => return error.Canceled,
            error.OutOfMemory => return internalError(request),
        }
    };
    return respond(request, if (result == .created) .created else .ok, "", null);
}

const ReadValueError = Allocator.Error || Request.ExpectContinueError || error{ ValueTooLarge, ReadFailed, EndOfStream };

/// Reads the whole request body, rejecting anything over `max_value_bytes`.
fn readValue(gpa: Allocator, request: *Request) ReadValueError![]u8 {
    if (request.head.content_length) |len| {
        // Refuse before sending `100 Continue`; `drainBody` handles the rest.
        if (len > max_value_bytes) return error.ValueTooLarge;
    }
    const body = (try bodyReader(request)) orelse return gpa.alloc(u8, 0);
    if (request.head.content_length) |len| {
        return body.readAlloc(gpa, @intCast(len));
    }
    return body.allocRemaining(gpa, .limited(max_value_bytes + 1)) catch |err| switch (err) {
        error.StreamTooLong => error.ValueTooLarge,
        else => |e| e,
    };
}

/// Returns a reader for the request body, or null if the request has none.
/// Unlike `Request.readerExpectContinue`, this honours a body on any method.
fn bodyReader(request: *Request) Request.ExpectContinueError!?*Io.Reader {
    const head = &request.head;
    if (head.transfer_encoding == .none and head.content_length == null) return null;
    if (head.expect != null) {
        try request.writeExpectContinue();
        try request.server.out.flush();
    }
    return request.server.reader.bodyReader(&.{}, head.transfer_encoding, head.content_length);
}

/// Consumes whatever is left of the request body (up to `max_drain_bytes`)
/// so that closing the socket does not reset the connection before the
/// client has read the response. Returns whether the body was fully consumed.
fn drainBody(request: *Request) bool {
    const state = &request.server.reader.state;
    if (state.* == .received_head) {
        if (request.head.expect != null) {
            // The client is waiting for permission to send; it never gets it.
            request.head.expect = null;
            return request.head.transfer_encoding == .none and request.head.content_length == null;
        }
        const body = bodyReader(request) catch return false;
        if (body == null) return true;
    }
    var drained: usize = 0;
    while (true) switch (state.*) {
        .ready => return true,
        .body_remaining_content_length, .body_remaining_chunk_len => {
            if (drained >= max_drain_bytes) return false;
            drained += request.server.reader.interface.discard(.limited(max_drain_bytes - drained)) catch return false;
        },
        else => return false,
    };
}

fn respond(request: *Request, status: http.Status, body: []const u8, content_type: ?[]const u8) Request.ExpectContinueError!void {
    return respondWith(request, status, body, if (content_type) |ct| &.{.{ .name = "content-type", .value = ct }} else &.{}, true);
}

fn methodNotAllowed(request: *Request, allow: []const u8) Request.ExpectContinueError!void {
    return respondWith(request, .method_not_allowed, "", &.{.{ .name = "allow", .value = allow }}, true);
}

fn internalError(request: *Request) Request.ExpectContinueError!void {
    return respondClose(request, .internal_server_error);
}

/// Responds with an empty body and closes the connection afterwards.
fn respondClose(request: *Request, status: http.Status) Request.ExpectContinueError!void {
    return respondWith(request, status, "", &.{}, false);
}

fn respondWith(
    request: *Request,
    status: http.Status,
    body: []const u8,
    extra_headers: []const http.Header,
    allow_keep_alive: bool,
) Request.ExpectContinueError!void {
    const drained = drainBody(request);
    try request.respond(body, .{
        .status = status,
        .keep_alive = allow_keep_alive and drained and request.head.keep_alive,
        .extra_headers = extra_headers,
    });
}

const testing = std.testing;

test resolveRoute {
    try testing.expectEqual(Route.health, resolveRoute("/health"));
    try testing.expectEqual(Route.list, resolveRoute("/kv"));
    try testing.expectEqual(Route.list, resolveRoute("/kv?x=1"));
    try testing.expectEqualStrings("a-B_9", resolveRoute("/kv/a-B_9").item);
    try testing.expectEqual(Route.invalid_key, resolveRoute("/kv/"));
    try testing.expectEqual(Route.invalid_key, resolveRoute("/kv/a/b"));
    try testing.expectEqual(Route.invalid_key, resolveRoute("/kv/bad.key"));
    try testing.expectEqual(Route.invalid_key, resolveRoute("/kv/a%20b"));
    try testing.expectEqual(Route.not_found, resolveRoute("/"));
    try testing.expectEqual(Route.not_found, resolveRoute("/health/"));
    try testing.expectEqual(Route.not_found, resolveRoute("/kvx"));
}

test isValidKey {
    try testing.expect(isValidKey("a"));
    try testing.expect(isValidKey("x" ** 64));
    try testing.expect(!isValidKey("x" ** 65));
    try testing.expect(!isValidKey(""));
    try testing.expect(!isValidKey("é"));
}
