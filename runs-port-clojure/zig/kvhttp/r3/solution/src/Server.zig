//! HTTP/1.1 front end for the key-value store.

const std = @import("std");
const Io = std.Io;
const http = std.http;
const net = Io.net;
const Allocator = std.mem.Allocator;
const Request = http.Server.Request;

const Store = @import("Store.zig");
const route = @import("route.zig");

const log = std.log.scoped(.kvhttp);

const Server = @This();

io: Io,
gpa: Allocator,
store: *Store,

/// Values are capped at 1 MiB; leave headroom so oversized bodies are
/// rejected cleanly rather than cut mid-read.
pub const max_body_len = 8 * 1024 * 1024;

/// Upper bound on the size of a request head (request line plus headers).
const max_head_len = 16 * 1024;

/// Accepts connections forever, serving each one on its own task.
pub fn serve(server: *const Server, listener: *net.Server) !void {
    var group: Io.Group = .init;
    defer group.cancel(server.io);

    while (true) {
        const stream = listener.accept(server.io) catch |err| switch (err) {
            error.ConnectionAborted, error.ProtocolFailure => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                log.warn("accept: {t}", .{err});
                continue;
            },
            else => |e| return e,
        };
        group.concurrent(server.io, serveConnection, .{ server, stream }) catch {
            // No spare worker: serve inline rather than dropping the client.
            serveConnection(server, stream);
        };
    }
}

fn serveConnection(server: *const Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [4096]u8 = undefined;
    var conn_reader = stream.reader(io, &recv_buffer);
    var conn_writer = stream.writer(io, &send_buffer);
    var http_server: http.Server = .init(&conn_reader.interface, &conn_writer.interface);

    while (true) {
        const keep_alive = server.serveRequest(&http_server) catch |err| {
            switch (err) {
                error.HttpConnectionClosing => {},
                error.ReadFailed => if (conn_reader.err) |e| log.debug("read: {t}", .{e}),
                error.WriteFailed => if (conn_writer.err) |e| log.debug("write: {t}", .{e}),
                else => log.debug("request: {t}", .{err}),
            }
            return;
        };
        if (!keep_alive) return;
    }
}

/// Serves one request. Returns whether the connection may be reused.
fn serveRequest(server: *const Server, http_server: *http.Server) !bool {
    const head_buffer = http_server.reader.receiveHead() catch |err| switch (err) {
        error.HttpHeadersOversize => {
            try respondRaw(http_server.out, .request_header_fields_too_large);
            return false;
        },
        else => |e| return e,
    };
    const head = Request.Head.parse(head_buffer) catch |err| {
        try respondRaw(http_server.out, statusForUnparsableHead(err, head_buffer));
        return false;
    };
    var request: Request = .{ .server = http_server, .head = head, .head_buffer = head_buffer };
    try server.handle(&request);
    return request.head.keep_alive and http_server.reader.state == .ready;
}

fn handle(server: *const Server, request: *Request) !void {
    const method = request.head.method;
    switch (route.match(request.head.target)) {
        .health => {
            try discardBody(request);
            if (method != .GET) return respondStatus(request, .method_not_allowed);
            try request.respond("ok", .{
                .keep_alive = request.head.keep_alive,
                .extra_headers = &.{.{ .name = "content-type", .value = "text/plain; charset=utf-8" }},
            });
        },
        .list => {
            try discardBody(request);
            if (method != .GET) return respondStatus(request, .method_not_allowed);
            try server.listKeys(request);
        },
        .entry => |target_key| {
            // The key points into the head buffer, which reading the body
            // may overwrite.
            var key_buffer: [route.max_key_len]u8 = undefined;
            const key = key_buffer[0..target_key.len];
            @memcpy(key, target_key);
            switch (method) {
                .GET => {
                    try discardBody(request);
                    try server.getEntry(request, key);
                },
                .PUT => try server.putEntry(request, key),
                .DELETE => {
                    try discardBody(request);
                    const status: http.Status = if (server.store.delete(server.io, key)) .no_content else .not_found;
                    try respondStatus(request, status);
                },
                else => {
                    try discardBody(request);
                    try respondStatus(request, .method_not_allowed);
                },
            }
        },
        .invalid_key => {
            try discardBody(request);
            try respondStatus(request, .bad_request);
        },
        .not_found => {
            try discardBody(request);
            try respondStatus(request, .not_found);
        },
    }
}

fn listKeys(server: *const Server, request: *Request) !void {
    const keys = try server.store.listKeys(server.io, server.gpa);
    defer {
        Store.freeKeys(server.gpa, keys);
        server.gpa.free(keys);
    }
    const json = try std.json.Stringify.valueAlloc(server.gpa, keys, .{});
    defer server.gpa.free(json);
    try request.respond(json, .{
        .keep_alive = request.head.keep_alive,
        .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
    });
}

fn getEntry(server: *const Server, request: *Request, key: []const u8) !void {
    const value = try server.store.fetch(server.io, server.gpa, key) orelse
        return respondStatus(request, .not_found);
    defer server.gpa.free(value);
    try request.respond(value, .{
        .keep_alive = request.head.keep_alive,
        .extra_headers = &.{.{ .name = "content-type", .value = "application/octet-stream" }},
    });
}

fn putEntry(server: *const Server, request: *Request, key: []const u8) !void {
    if (request.head.content_length) |len| if (len > max_body_len) {
        // Do not read the oversized body; the connection is closed after this.
        return request.respond("", .{ .status = .payload_too_large, .keep_alive = false });
    };
    const value = if (try bodyReader(request)) |body|
        body.allocRemaining(server.gpa, .limited(max_body_len)) catch |err| switch (err) {
            error.StreamTooLong => return request.respond("", .{ .status = .payload_too_large, .keep_alive = false }),
            else => |e| return e,
        }
    else
        try server.gpa.alloc(u8, 0);
    defer server.gpa.free(value);

    const status: http.Status = switch (try server.store.put(server.io, key, value)) {
        .created => .created,
        .replaced => .ok,
    };
    try respondStatus(request, status);
}

fn respondStatus(request: *Request, status: http.Status) !void {
    try request.respond("", .{ .status = status, .keep_alive = request.head.keep_alive });
}

/// Returns a reader for the request body, or null if the request has none.
///
/// Unlike `Request.readerExpectNone`, this honors the framing headers for
/// every method, so a body sent with e.g. GET is still consumed.
fn bodyReader(request: *Request) !?*Io.Reader {
    if (request.head.transfer_encoding == .none and request.head.content_length == null) return null;
    if (request.head.expect != null) {
        try request.writeExpectContinue();
        try request.server.out.flush();
    }
    return request.server.reader.bodyReader(&.{}, request.head.transfer_encoding, request.head.content_length);
}

/// Consumes and drops any request body so that closing the socket does not
/// reset the connection before the client has read the response.
fn discardBody(request: *Request) !void {
    const body = try bodyReader(request) orelse return;
    _ = body.discardRemaining() catch |err| switch (err) {
        error.ReadFailed => return err,
    };
}

fn statusForUnparsableHead(err: Request.Head.ParseError, head_buffer: []const u8) http.Status {
    if (err != error.UnknownHttpMethod) return .bad_request;
    // An unlisted method on a known resource is still a 405.
    var parts = std.mem.tokenizeScalar(u8, std.mem.sliceTo(head_buffer, '\r'), ' ');
    _ = parts.next();
    const target = parts.next() orelse return .bad_request;
    return switch (route.match(target)) {
        .not_found => .not_found,
        .invalid_key => .bad_request,
        .health, .list, .entry => .method_not_allowed,
    };
}

/// Writes a bodiless response for a request that could not be parsed.
fn respondRaw(out: *Io.Writer, status: http.Status) !void {
    try out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-length: 0\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try out.flush();
}

test statusForUnparsableHead {
    const t = std.testing;
    try t.expectEqual(http.Status.method_not_allowed, statusForUnparsableHead(error.UnknownHttpMethod, "PURGE /kv/a HTTP/1.1\r\n\r\n"));
    try t.expectEqual(http.Status.not_found, statusForUnparsableHead(error.UnknownHttpMethod, "PURGE /x HTTP/1.1\r\n\r\n"));
    try t.expectEqual(http.Status.bad_request, statusForUnparsableHead(error.UnknownHttpMethod, "PURGE /kv/a.b HTTP/1.1\r\n\r\n"));
    try t.expectEqual(http.Status.bad_request, statusForUnparsableHead(error.HttpHeadersInvalid, "GET /kv/a HTTP/1.1\r\n\r\n"));
}
