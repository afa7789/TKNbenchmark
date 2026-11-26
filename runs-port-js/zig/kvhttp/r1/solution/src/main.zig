//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: kvhttp <port>
//! Listens on 127.0.0.1:<port>; each connection is served on its own task.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const http = std.http;
const Request = http.Server.Request;

const Store = @import("Store.zig");
const route = @import("route.zig");

const log = std.log.scoped(.kvhttp);

/// Largest accepted request body (and therefore stored value).
const max_value_len = 1024 * 1024;
/// When rejecting an oversized body, read and drop up to this many more bytes
/// so that closing the socket does not reset the connection before the client
/// has seen the response.
const max_drain_len = 16 * 1024 * 1024;
/// Upper bound on the size of a request head (request line plus headers).
const max_head_len = 16 * 1024;

const text_plain: http.Header = .{ .name = "content-type", .value = "text/plain; charset=utf-8" };
const application_json: http.Header = .{ .name = "content-type", .value = "application/json" };
const octet_stream: http.Header = .{ .name = "content-type", .value = "application/octet-stream" };

const Context = struct {
    gpa: Allocator,
    io: Io,
    store: *Store,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const port = parsePort(init.minimal.args, init.arena.allocator()) orelse {
        std.log.err("usage: app <port>", .{});
        std.process.exit(2);
    };

    var store: Store = .init(gpa);
    defer store.deinit();
    const ctx: Context = .{ .gpa = gpa, .io = io, .store = &store };

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }) catch |err| {
        std.log.err("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
        std.process.exit(1);
    };
    defer listener.deinit(io);

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled, error.SocketNotListening => return err,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, serveConnection, .{ &ctx, stream }) catch {
            // No thread available: serve inline rather than dropping the client.
            serveConnection(&ctx, stream);
        };
    }
}

fn parsePort(args: std.process.Args, arena: Allocator) ?u16 {
    var it = args.iterateAllocator(arena) catch return null;
    _ = it.skip();
    const text = it.next() orelse return null;
    const port = std.fmt.parseInt(u16, text, 10) catch return null;
    return if (port == 0) null else port;
}

fn serveConnection(ctx: *const Context, stream: Io.net.Stream) void {
    const io = ctx.io;
    defer stream.close(io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [16 * 1024]u8 = undefined;
    var conn_reader = stream.reader(io, &recv_buffer);
    var conn_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&conn_reader.interface, &conn_writer.interface);

    var arena_state: std.heap.ArenaAllocator = .init(ctx.gpa);
    defer arena_state.deinit();

    while (true) {
        defer _ = arena_state.reset(.retain_capacity);
        const keep_alive = serveRequest(ctx, &server, arena_state.allocator()) catch |err| {
            switch (err) {
                error.WriteFailed => log.debug("write failed: {t}", .{conn_writer.err orelse err}),
                error.ReadFailed => log.debug("read failed: {t}", .{conn_reader.err orelse err}),
                else => log.debug("connection dropped: {t}", .{err}),
            }
            return;
        };
        if (!keep_alive) return;
    }
}

const ServeError = error{ ReadFailed, WriteFailed, HttpRequestTruncated, OutOfMemory };

/// Serves one request. Returns whether the connection may be reused.
fn serveRequest(ctx: *const Context, server: *http.Server, arena: Allocator) ServeError!bool {
    const head_buffer = server.reader.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return false,
        error.HttpHeadersOversize => {
            try writeBareResponse(server.out, .request_header_fields_too_large, null);
            return false;
        },
        error.HttpRequestTruncated, error.ReadFailed => |e| return e,
    };
    const head = Request.Head.parse(head_buffer) catch |err| {
        if (err == error.UnknownHttpMethod) {
            try respondUnknownMethod(server.out, head_buffer);
        } else {
            try writeBareResponse(server.out, .bad_request, null);
        }
        return false;
    };
    var request: Request = .{ .server = server, .head = head, .head_buffer = head_buffer };

    // Reading the body invalidates the strings in `request.head`.
    const method = request.head.method;
    const path = try arena.dupe(u8, request.head.target);

    // Like the reference implementation, always consume the body before
    // routing so error responses do not reset the connection.
    var body = readBody(ctx.gpa, &request, method == .PUT) catch |err| switch (err) {
        error.HttpExpectationFailed => {
            request.head.expect = null;
            try respondError(&request, .expectation_failed, false);
            return false;
        },
        error.ValueTooLarge => {
            try respondError(&request, .payload_too_large, false);
            return false;
        },
        error.MalformedBody => {
            try writeBareResponse(server.out, .bad_request, null);
            return false;
        },
        error.ReadFailed, error.WriteFailed, error.OutOfMemory => |e| return e,
    };
    defer if (body) |b| ctx.gpa.free(b);

    const keep_alive = request.head.keep_alive;

    const endpoint = switch (route.resolve(path)) {
        .endpoint => |e| e,
        .failure => |status| {
            try respondError(&request, status, keep_alive);
            return keep_alive;
        },
    };
    if (!endpoint.allows(method)) {
        try respond(&request, http.Status.method_not_allowed.phrase().?, .{
            .status = .method_not_allowed,
            .keep_alive = keep_alive,
            .extra_headers = &.{ text_plain, .{ .name = "allow", .value = endpoint.allow() } },
        });
        return keep_alive;
    }

    switch (endpoint) {
        .health => try respond(&request, "ok", .{ .keep_alive = keep_alive, .extra_headers = &.{text_plain} }),
        .list => {
            const keys = try ctx.store.sortedKeys(ctx.io, arena);
            var json: Io.Writer.Allocating = .init(arena);
            std.json.Stringify.value(keys, .{}, &json.writer) catch return error.OutOfMemory;
            try respond(&request, json.written(), .{ .keep_alive = keep_alive, .extra_headers = &.{application_json} });
        },
        .item => |key| switch (method) {
            .GET => {
                const value = try ctx.store.get(ctx.io, arena, key) orelse {
                    try respondError(&request, .not_found, keep_alive);
                    return keep_alive;
                };
                try respond(&request, value, .{ .keep_alive = keep_alive, .extra_headers = &.{octet_stream} });
            },
            .PUT => {
                const value = body orelse try ctx.gpa.alloc(u8, 0);
                const result = ctx.store.put(ctx.io, key, value) catch |err| {
                    body = value; // still ours to free
                    return err;
                };
                body = null; // now owned by the store
                const status: http.Status = switch (result) {
                    .created => .created,
                    .replaced => .ok,
                };
                try respond(&request, "", .{ .status = status, .keep_alive = keep_alive });
            },
            .DELETE => {
                if (!ctx.store.remove(ctx.io, key)) {
                    try respondError(&request, .not_found, keep_alive);
                    return keep_alive;
                }
                // A 204 carries no Content-Length; std.http closes the
                // connection after such a response.
                try respond(&request, "", .{ .status = .no_content, .transfer_encoding = .none });
                return false;
            },
            else => unreachable, // filtered by `allows`
        },
    }
    return keep_alive;
}

const BodyError = error{
    HttpExpectationFailed,
    ValueTooLarge,
    MalformedBody,
    ReadFailed,
    WriteFailed,
    OutOfMemory,
};

/// Consumes the request body. When `keep` is set, returns it as a slice owned
/// by `gpa`; otherwise discards it and returns null. Bodies larger than
/// `max_value_len` are rejected either way.
fn readBody(gpa: Allocator, request: *Request, keep: bool) BodyError!?[]u8 {
    const head = request.head;
    // A request without framing headers has an empty body.
    const content_length: ?u64 = if (head.transfer_encoding == .chunked) null else head.content_length orelse 0;

    if (head.expect != null) {
        if (content_length) |len| if (len > max_value_len) {
            // Reject before the client sends the body.
            request.head.expect = null;
            return error.ValueTooLarge;
        };
        try request.writeExpectContinue();
        try request.server.out.flush();
    }

    const http_reader = &request.server.reader;
    const reader = http_reader.bodyReader(&.{}, head.transfer_encoding, content_length);

    if (content_length) |len| {
        if (len > max_value_len) {
            drain(reader);
            return error.ValueTooLarge;
        }
        if (!keep) {
            _ = reader.discardRemaining() catch return error.ReadFailed;
            return null;
        }
        const value = try gpa.alloc(u8, @intCast(len));
        errdefer gpa.free(value);
        reader.readSliceAll(value) catch return error.ReadFailed;
        return value;
    }

    // Chunked: the size is only known once the whole body has been read.
    const value = reader.allocRemaining(gpa, .limited(max_value_len + 1)) catch |err| switch (err) {
        error.StreamTooLong => {
            drain(reader);
            return error.ValueTooLarge;
        },
        error.ReadFailed => return if (http_reader.body_err != null) error.MalformedBody else error.ReadFailed,
        error.OutOfMemory => |e| return e,
    };
    if (keep) return value;
    gpa.free(value);
    return null;
}

/// Best-effort discard of an unwanted body before the connection is closed.
fn drain(reader: *Io.Reader) void {
    var remaining: usize = max_drain_len;
    while (remaining > 0) {
        remaining -= reader.discard(.limited(remaining)) catch return;
    }
}

/// `Request.respond`, for requests whose `Expect` header was already handled
/// by `readBody`.
fn respond(request: *Request, content: []const u8, options: Request.RespondOptions) Io.Writer.Error!void {
    std.debug.assert(request.head.expect == null);
    request.respond(content, options) catch |err| switch (err) {
        error.HttpExpectationFailed => unreachable,
        error.WriteFailed => |e| return e,
    };
}

fn respondError(request: *Request, status: http.Status, keep_alive: bool) Io.Writer.Error!void {
    try respond(request, status.phrase() orelse "", .{
        .status = status,
        .keep_alive = keep_alive,
        .extra_headers = &.{text_plain},
    });
}

/// `std.http.Server` only parses the methods in `std.http.Method`. Any other
/// method token is never allowed, so answer from the path alone.
fn respondUnknownMethod(out: *Io.Writer, head_buffer: []const u8) Io.Writer.Error!void {
    const request_line = head_buffer[0 .. std.mem.indexOf(u8, head_buffer, "\r\n") orelse head_buffer.len];
    var parts = std.mem.tokenizeScalar(u8, request_line, ' ');
    const method = parts.next() orelse "";
    const target = parts.next() orelse "";
    if (!isToken(method) or parts.next() == null) return writeBareResponse(out, .bad_request, null);

    switch (route.resolve(target)) {
        .endpoint => |e| try writeBareResponse(out, .method_not_allowed, e.allow()),
        .failure => |status| try writeBareResponse(out, status, null),
    }
}

/// Writes a complete plain-text response for a request that could not be
/// parsed, then expects the connection to be closed.
fn writeBareResponse(out: *Io.Writer, status: http.Status, allow: ?[]const u8) Io.Writer.Error!void {
    const phrase = status.phrase() orelse "";
    try out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-type: {s}\r\ncontent-length: {d}\r\n", .{
        @intFromEnum(status), phrase, text_plain.value, phrase.len,
    });
    if (allow) |value| try out.print("allow: {s}\r\n", .{value});
    try out.print("\r\n{s}", .{phrase});
    try out.flush();
}

/// RFC 9110 `token`: one or more tchar.
fn isToken(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
        else => return false,
    };
    return true;
}

test {
    _ = Store;
    _ = route;
}
