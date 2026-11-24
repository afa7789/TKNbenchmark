//! kvhttp: an in-memory key-value store served over HTTP/1.1.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port>)

const std = @import("std");
const Io = std.Io;
const http = std.http;
const Allocator = std.mem.Allocator;
const Request = http.Server.Request;

const Store = @import("Store.zig");
const routing = @import("routing.zig");

const log = std.log.scoped(.kvhttp);

pub const max_value_len = 1024 * 1024;
/// Upper bound on the size of a request head (request line plus headers).
const max_head_len = 16 * 1024;

pub const std_options: std.Options = .{ .log_level = .warn };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const port_arg = args.next() orelse fatal("usage: app <port>", .{});
    const port = std.fmt.parseInt(u16, port_arg, 10) catch fatal("invalid port: {s}", .{port_arg});

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .reuse_address = true }) catch |err|
        fatal("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer listener.deinit(io);

    var store: Store = .init(gpa);
    defer store.deinit();

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, handleConnection, .{ io, gpa, &store, stream }) catch {
            // No spare concurrency; serve this client inline rather than drop it.
            handleConnection(io, gpa, &store, stream);
        };
    }
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

const Connection = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
    server: *http.Server,
};

fn handleConnection(io: Io, gpa: Allocator, store: *Store, stream: Io.net.Stream) void {
    defer stream.close(io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    const conn: Connection = .{ .io = io, .gpa = gpa, .store = store, .server = &server };
    while (true) {
        const keep_alive = serveRequest(conn) catch |err| {
            switch (err) {
                error.ReadFailed => if (stream_reader.err) |e| log.debug("read: {t}", .{e}),
                error.WriteFailed => if (stream_writer.err) |e| log.debug("write: {t}", .{e}),
                else => log.debug("connection error: {t}", .{err}),
            }
            return;
        };
        if (!keep_alive) return;
    }
}

const ServeError = Allocator.Error || Io.Cancelable || Io.Writer.Error || Io.Reader.Error ||
    Request.ExpectContinueError;

/// Reads and answers one request. Returns whether the connection may be reused.
fn serveRequest(conn: Connection) ServeError!bool {
    const server = conn.server;
    const head_buffer = server.reader.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing, error.HttpRequestTruncated => return false,
        error.HttpHeadersOversize => {
            try writeBareResponse(server.out, .request_header_fields_too_large);
            return false;
        },
        error.ReadFailed => |e| return e,
    };

    const head = Request.Head.parse(head_buffer) catch |err| {
        // std.http only knows the standard methods; any other token still
        // deserves 404/400/405 according to the path it targets.
        const status: http.Status = switch (err) {
            error.UnknownHttpMethod => unknownMethodStatus(head_buffer),
            error.HttpTransferEncodingUnsupported, error.CompressionUnsupported => .not_implemented,
            else => .bad_request,
        };
        try writeBareResponse(server.out, status);
        return false;
    };
    var request: Request = .{ .server = server, .head = head, .head_buffer = head_buffer };

    if (request.head.expect) |expect| {
        if (!std.ascii.eqlIgnoreCase(expect, "100-continue")) {
            request.head.expect = null;
            try respond(&request, .expectation_failed, "", .{ .keep_alive = false });
            return false;
        }
        // Expectation tokens are case-insensitive, but std.http compares exactly.
        request.head.expect = "100-continue";
    }

    const route = switch (routing.resolve(@tagName(request.head.method), request.head.target)) {
        .route => |r| r,
        .reject => |status| {
            try discardBody(&request);
            try respond(&request, status, "", .{});
            return request.head.keep_alive;
        },
    };

    switch (route) {
        .health => {
            try discardBody(&request);
            try respond(&request, .ok, "ok", .{ .content_type = "text/plain" });
        },
        .list => {
            try discardBody(&request);
            var json: Io.Writer.Allocating = .init(conn.gpa);
            defer json.deinit();
            conn.store.writeKeysJson(conn.io, conn.gpa, &json.writer) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                else => |e| return e,
            };
            try respond(&request, .ok, json.written(), .{ .content_type = "application/json" });
        },
        .get => |key| {
            try discardBody(&request);
            if (try conn.store.getCopy(conn.io, conn.gpa, key.slice())) |value| {
                defer conn.gpa.free(value);
                try respond(&request, .ok, value, .{ .content_type = "application/octet-stream" });
            } else {
                try respond(&request, .not_found, "", .{});
            }
        },
        .delete => |key| {
            try discardBody(&request);
            const status: http.Status = if (try conn.store.delete(conn.io, key.slice())) .no_content else .not_found;
            try respond(&request, status, "", .{});
        },
        .put => |key| {
            const value = readValue(conn.gpa, &request) catch |err| switch (err) {
                error.ValueTooLarge => {
                    try respond(&request, .payload_too_large, "", .{ .keep_alive = false });
                    return false;
                },
                else => |e| return e,
            };
            const status: http.Status = switch (try conn.store.put(conn.io, key.slice(), value)) {
                .created => .created,
                .replaced => .ok,
            };
            try respond(&request, status, "", .{});
        },
    }
    return request.head.keep_alive;
}

/// Prepares to read the request body, whatever the method. Reading it all
/// (rather than leaving bytes unread) matters even when closing: closing a
/// socket with unread input makes the kernel send RST, which can destroy the
/// response before the client reads it.
///
/// Invalidates the string memory in `request.head`.
fn bodyReader(request: *Request) Request.ExpectContinueError!*Io.Reader {
    const head = &request.head;
    if (head.transfer_encoding == .none and head.content_length == null) {
        // No body; the next request (if any) starts right after the head.
        head.expect = null;
        request.server.reader.state = .ready;
        return Io.Reader.ending;
    }
    if (head.expect != null) {
        try request.writeExpectContinue();
        try request.server.out.flush();
    }
    return request.server.reader.bodyReader(&.{}, head.transfer_encoding, head.content_length);
}

fn discardBody(request: *Request) ServeError!void {
    const body = try bodyReader(request);
    _ = try body.discardRemaining();
}

/// Reads the request body into a buffer owned by the caller.
fn readValue(gpa: Allocator, request: *Request) (ServeError || error{ValueTooLarge})![]u8 {
    if (request.head.content_length) |len| {
        if (len > max_value_len) return error.ValueTooLarge;
    }
    const known_len = request.head.content_length;
    const body = try bodyReader(request);
    if (known_len) |len| {
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

const RespondOptions = struct {
    content_type: ?[]const u8 = null,
    keep_alive: bool = true,
};

fn respond(request: *Request, status: http.Status, body: []const u8, options: RespondOptions) Request.ExpectContinueError!void {
    var headers_buf: [1]http.Header = undefined;
    var headers: []const http.Header = &.{};
    if (options.content_type) |ct| {
        headers_buf[0] = .{ .name = "content-type", .value = ct };
        headers = &headers_buf;
    }
    try request.respond(body, .{
        .status = status,
        .keep_alive = options.keep_alive,
        .extra_headers = headers,
    });
}

/// Writes a body-less response and signals that the connection will close.
/// Used when the request head could not be parsed into a `Request`.
fn writeBareResponse(out: *Io.Writer, status: http.Status) Io.Writer.Error!void {
    try out.print("HTTP/1.1 {d} {s}\r\ncontent-length: 0\r\nconnection: close\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try out.flush();
}

fn unknownMethodStatus(head_buffer: []const u8) http.Status {
    const line_end = std.mem.indexOf(u8, head_buffer, "\r\n") orelse head_buffer.len;
    var parts = std.mem.tokenizeScalar(u8, head_buffer[0..line_end], ' ');
    const method = parts.next() orelse return .bad_request;
    const target = parts.next() orelse return .bad_request;
    return switch (routing.resolve(method, target)) {
        .reject => |status| status,
        // Only standard methods map to routes, and those parse successfully.
        .route => .method_not_allowed,
    };
}

test unknownMethodStatus {
    try std.testing.expectEqual(.method_not_allowed, unknownMethodStatus("FROB /kv/a HTTP/1.1\r\n\r\n"));
    try std.testing.expectEqual(.bad_request, unknownMethodStatus("FROB /kv/a.b HTTP/1.1\r\n\r\n"));
    try std.testing.expectEqual(.not_found, unknownMethodStatus("FROB /x HTTP/1.1\r\n\r\n"));
}

test {
    _ = Store;
    _ = routing;
}
