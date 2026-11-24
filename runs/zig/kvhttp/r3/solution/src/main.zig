//! kvhttp: an HTTP/1.1 in-memory key/value server.
//!
//! Usage: app <port>
//! Listens on 127.0.0.1:<port>; one request is served per connection.

const std = @import("std");
const Io = std.Io;
const http = std.http;
const net = Io.net;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const routing = @import("routing.zig");
const Route = routing.Route;

/// Largest accepted value, in bytes.
const max_value_len = 1024 * 1024;
/// Largest accepted request head, in bytes.
const max_head_len = 16 * 1024;

const log = std.log.scoped(.kvhttp);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const port = parsePort(init.minimal.args) catch {
        std.debug.print("usage: app <port>\n", .{});
        std.process.exit(2);
    };

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer listener.deinit(io);

    var store: Store = .init(gpa);
    defer store.deinit();

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            error.ConnectionAborted, error.WouldBlock => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        group.concurrent(io, serveConnection, .{ io, gpa, &store, stream }) catch {
            // No thread available for concurrency; serve inline rather than drop.
            serveConnection(io, gpa, &store, stream) catch |err| return err;
        };
    }
}

fn parsePort(args: std.process.Args) !u16 {
    var it = args.iterate();
    _ = it.skip();
    const arg = it.next() orelse return error.MissingPort;
    if (it.next() != null) return error.TooManyArguments;
    return std.fmt.parseInt(u16, arg, 10);
}

fn serveConnection(io: Io, gpa: Allocator, store: *Store, stream: net.Stream) Io.Cancelable!void {
    defer stream.close(io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    handleRequest(io, gpa, store, &server) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        // The peer went away or misbehaved at the transport level; there is
        // nobody left to report to.
        error.ReadFailed, error.WriteFailed, error.ConnectionClosed => {},
    };
}

const HandleError = error{ ReadFailed, WriteFailed, ConnectionClosed } || Io.Cancelable;

fn handleRequest(io: Io, gpa: Allocator, store: *Store, server: *http.Server) HandleError!void {
    const head_buffer = server.reader.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing, error.HttpRequestTruncated => return error.ConnectionClosed,
        error.ReadFailed => return error.ReadFailed,
        error.HttpHeadersOversize => return sendRaw(server.out, .request_header_fields_too_large),
    };

    const head = http.Server.Request.Head.parse(head_buffer) catch |err| switch (err) {
        // `std.http.Method` only knows the standard methods. Anything else is
        // still a method the route does not list, so route on the path alone.
        error.UnknownHttpMethod => return sendRaw(server.out, unknownMethodStatus(head_buffer)),
        else => return sendRaw(server.out, .bad_request),
    };

    var request: http.Server.Request = .{ .server = server, .head = head, .head_buffer = head_buffer };
    // Copy the route out of the head now: reading the body invalidates it.
    const route = routing.route(head.target);

    switch (route) {
        .not_found => return respond(&request, .not_found, ""),
        .bad_key => return respond(&request, .bad_request, ""),
        .health => switch (head.method) {
            .GET => return respond(&request, .ok, "ok"),
            else => return respond(&request, .method_not_allowed, ""),
        },
        .list => switch (head.method) {
            .GET => {
                const json = store.keysJson(io, gpa) catch |err| switch (err) {
                    error.OutOfMemory => return respond(&request, .internal_server_error, ""),
                    error.Canceled => return error.Canceled,
                };
                defer gpa.free(json);
                return request.respond(json, .{
                    .status = .ok,
                    .keep_alive = false,
                    .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
                }) catch |err| return mapRespondError(err);
            },
            else => return respond(&request, .method_not_allowed, ""),
        },
        .item => |*key_buf| {
            const key = key_buf.slice();
            switch (head.method) {
                .GET => {
                    const value = store.get(io, gpa, key) catch |err| switch (err) {
                        error.OutOfMemory => return respond(&request, .internal_server_error, ""),
                        error.Canceled => return error.Canceled,
                    } orelse return respond(&request, .not_found, "");
                    defer gpa.free(value);
                    return respond(&request, .ok, value);
                },
                .DELETE => {
                    const removed = try store.remove(io, key);
                    return respond(&request, if (removed) .no_content else .not_found, "");
                },
                .PUT => {
                    const value = readBody(&request, gpa) catch |err| switch (err) {
                        error.ReadFailed => return error.ReadFailed,
                        error.WriteFailed => return error.WriteFailed,
                        error.HttpExpectationFailed => return respond(&request, .expectation_failed, ""),
                        error.StreamTooLong => return respond(&request, .payload_too_large, ""),
                        error.OutOfMemory => return respond(&request, .internal_server_error, ""),
                    };
                    const result = store.put(io, key, value) catch |err| {
                        gpa.free(value);
                        switch (err) {
                            error.OutOfMemory => return respond(&request, .internal_server_error, ""),
                            error.Canceled => return error.Canceled,
                        }
                    };
                    return respond(&request, switch (result) {
                        .created => .created,
                        .replaced => .ok,
                    }, "");
                },
                else => return respond(&request, .method_not_allowed, ""),
            }
        },
    }
}

const ReadBodyError = error{ ReadFailed, WriteFailed, HttpExpectationFailed, StreamTooLong, OutOfMemory };

/// Reads the complete request body, allocated with `gpa`.
fn readBody(request: *http.Server.Request, gpa: Allocator) ReadBodyError![]u8 {
    if (request.head.content_length) |len| {
        if (len > max_value_len) return error.StreamTooLong;
    } else if (request.head.transfer_encoding == .none) {
        // RFC 9112 §6.3: without Content-Length or Transfer-Encoding a
        // request has no body. (`std.http` would otherwise read until EOF.)
        return gpa.alloc(u8, 0);
    }
    var transfer_buffer: [4096]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&transfer_buffer);
    return body_reader.allocRemaining(gpa, .limited(max_value_len + 1)) catch |err| switch (err) {
        error.ReadFailed => error.ReadFailed,
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
    };
}

/// Sends a complete response and marks the connection for closing.
fn respond(request: *http.Server.Request, status: http.Status, body: []const u8) HandleError!void {
    request.respond(body, .{ .status = status, .keep_alive = false }) catch |err| return mapRespondError(err);
}

fn mapRespondError(err: http.Server.Request.ExpectContinueError) HandleError {
    return switch (err) {
        error.WriteFailed => error.WriteFailed,
        // Only reachable for requests whose body we never read; the response
        // already went out without a 100-continue, which is still valid.
        error.HttpExpectationFailed => error.WriteFailed,
    };
}

/// Writes a bodiless response directly, for requests `std.http` cannot
/// represent. The connection is closed afterwards.
fn sendRaw(out: *Io.Writer, status: http.Status) HandleError!void {
    out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-length: 0\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    }) catch return error.WriteFailed;
    out.flush() catch return error.WriteFailed;
}

/// Status for a request whose method `std.http` does not recognize.
fn unknownMethodStatus(head_buffer: []const u8) http.Status {
    const line_end = std.mem.indexOfScalar(u8, head_buffer, '\r') orelse head_buffer.len;
    var parts = std.mem.tokenizeScalar(u8, head_buffer[0..line_end], ' ');
    _ = parts.next() orelse return .bad_request;
    const target = parts.next() orelse return .bad_request;
    return switch (routing.route(target)) {
        .not_found => .not_found,
        .bad_key => .bad_request,
        .health, .list, .item => .method_not_allowed,
    };
}

test {
    _ = Store;
    _ = routing;
}
