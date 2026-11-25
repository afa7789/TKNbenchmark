//! kvhttp: an HTTP/1.1 in-memory key-value server.
const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const route = @import("route.zig");

const max_value_len = 1 << 20;
const max_head_len = 16 * 1024;

const log = std.log.scoped(.kvhttp);

pub const std_options: std.Options = .{ .log_level = .warn };

const App = struct {
    io: Io,
    gpa: Allocator,
    store: Store,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) std.process.fatal("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
    const port = std.fmt.parseInt(u16, args[1], 10) catch
        std.process.fatal("invalid port: {s}", .{args[1]});

    var app: App = .{ .io = io, .gpa = init.gpa, .store = .init(init.gpa) };
    defer app.store.deinit();

    const address = try net.IpAddress.parse("127.0.0.1", port);
    var listener = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer listener.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            error.ConnectionAborted, error.ProtocolFailure, error.WouldBlock => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
        };
        group.concurrent(io, serveConnection, .{ &app, stream }) catch {
            // No thread available: serve inline rather than drop the client.
            serveConnection(&app, stream);
        };
    }
}

fn serveConnection(app: *App, stream: net.Stream) void {
    const io = app.io;
    defer stream.close(io);

    var in_buf: [max_head_len]u8 = undefined;
    var out_buf: [16 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &in_buf);
    var stream_writer = stream.writer(io, &out_buf);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    while (true) {
        const keep_alive = serveRequest(app, &server) catch |err| {
            switch (err) {
                error.HttpConnectionClosing, error.ReadFailed, error.WriteFailed, error.Canceled => {},
                else => log.debug("connection error: {t}", .{err}),
            }
            return;
        };
        if (!keep_alive) return;
    }
}

const ServeError = http.Server.ReceiveHeadError || http.Server.Request.ExpectContinueError ||
    Io.Writer.Error || Io.Reader.Error || Allocator.Error || Io.Cancelable;

/// Handles one request. Returns whether the connection may be reused.
fn serveRequest(app: *App, server: *http.Server) ServeError!bool {
    const head_buffer = server.reader.receiveHead() catch |err| switch (err) {
        error.HttpHeadersOversize => {
            try respondRaw(server.out, .request_header_fields_too_large);
            return false;
        },
        else => return err,
    };
    const head = http.Server.Request.Head.parse(head_buffer) catch |err| {
        const status: http.Status = switch (err) {
            // A method we do not know cannot be one any route lists.
            error.UnknownHttpMethod => switch (route.resolve(.other, requestTarget(head_buffer))) {
                .not_found => .not_found,
                .bad_key => .bad_request,
                else => .method_not_allowed,
            },
            else => .bad_request,
        };
        try respondRaw(server.out, status);
        return false;
    };
    var request: http.Server.Request = .{ .server = server, .head = head, .head_buffer = head_buffer };

    const method: route.Method = switch (head.method) {
        .GET => .GET,
        .PUT => .PUT,
        .DELETE => .DELETE,
        else => .other,
    };

    // The head lives in the read buffer, which reading the body may
    // overwrite, so copy the key out first.
    var key_buf: [route.max_key_len]u8 = undefined;
    const r: route.Route = switch (route.resolve(method, head.target)) {
        inline .get, .put, .delete => |key, tag| blk: {
            @memcpy(key_buf[0..key.len], key);
            break :blk @unionInit(route.Route, @tagName(tag), key_buf[0..key.len]);
        },
        else => |other| other,
    };

    // Always consume the request body so the connection stays in sync and
    // closing it does not reset the peer before it reads our response.
    const body = readBody(app.gpa, &request) catch |err| switch (err) {
        error.StreamTooLong => {
            try respond(&request, .payload_too_large, "", false);
            return false;
        },
        else => |e| return e,
    };
    defer app.gpa.free(body);

    const keep_alive = head.keep_alive;
    switch (r) {
        .health => try respond(&request, .ok, "ok", keep_alive),
        .list => {
            var aw: Io.Writer.Allocating = .init(app.gpa);
            defer aw.deinit();
            app.store.writeKeysJson(app.io, app.gpa, &aw.writer) catch |err| switch (err) {
                error.WriteFailed => return error.OutOfMemory,
                else => |e| return e,
            };
            try request.respond(aw.written(), .{
                .keep_alive = keep_alive,
                .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
            });
        },
        .get => |key| {
            const value = try app.store.getCopy(app.io, app.gpa, key) orelse
                return respondKeepAlive(&request, .not_found, keep_alive);
            defer app.gpa.free(value);
            try respond(&request, .ok, value, keep_alive);
        },
        .put => |key| {
            const value = try app.gpa.dupe(u8, body);
            const result = app.store.put(app.io, key, value) catch |err| {
                app.gpa.free(value);
                return err;
            };
            const status: http.Status = switch (result) {
                .created => .created,
                .replaced => .ok,
            };
            try respond(&request, status, "", keep_alive);
        },
        .delete => |key| {
            const status: http.Status = if (try app.store.remove(app.io, key)) .no_content else .not_found;
            try respond(&request, status, "", keep_alive);
        },
        .bad_key => try respond(&request, .bad_request, "", keep_alive),
        .not_found => try respond(&request, .not_found, "", keep_alive),
        .method_not_allowed => try respond(&request, .method_not_allowed, "", keep_alive),
    }
    return keep_alive;
}

fn respondKeepAlive(request: *http.Server.Request, status: http.Status, keep_alive: bool) ServeError!bool {
    try respond(request, status, "", keep_alive);
    return keep_alive;
}

fn respond(request: *http.Server.Request, status: http.Status, body: []const u8, keep_alive: bool) ServeError!void {
    try request.respond(body, .{ .status = status, .keep_alive = keep_alive });
}

/// Reads the whole request body regardless of method, up to `max_value_len`
/// bytes; `error.StreamTooLong` beyond that.
fn readBody(gpa: Allocator, request: *http.Server.Request) (ServeError || error{StreamTooLong})![]u8 {
    const head = &request.head;
    if (head.expect) |expect| {
        if (!std.mem.eql(u8, expect, "100-continue")) return error.HttpExpectationFailed;
        if ((head.content_length orelse 1) > 0) {
            try request.server.out.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
            try request.server.out.flush();
        }
        head.expect = null;
    }
    if (head.content_length) |len| if (len > max_value_len) return error.StreamTooLong;
    if (head.transfer_encoding == .none and head.content_length == null) {
        request.server.reader.state = .ready;
        return gpa.alloc(u8, 0);
    }
    var transfer_buf: [4096]u8 = undefined;
    const body_reader = request.server.reader.bodyReader(&transfer_buf, head.transfer_encoding, head.content_length);
    return body_reader.allocRemaining(gpa, .limited(max_value_len + 1));
}

/// Extracts the request target from the request line of an unparsed head.
fn requestTarget(head_buffer: []const u8) []const u8 {
    const line_end = std.mem.indexOfScalar(u8, head_buffer, '\r') orelse head_buffer.len;
    var it = std.mem.tokenizeScalar(u8, head_buffer[0..line_end], ' ');
    _ = it.next();
    return it.next() orelse "";
}

/// Writes a bodiless response for a request that could not be parsed.
fn respondRaw(out: *Io.Writer, status: http.Status) Io.Writer.Error!void {
    try out.print("HTTP/1.1 {d} {s}\r\ncontent-length: 0\r\nconnection: close\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try out.flush();
}

test {
    _ = Store;
    _ = route;
}

test requestTarget {
    try std.testing.expectEqualStrings("/kv/a", requestTarget("FOO /kv/a HTTP/1.1\r\n\r\n"));
    try std.testing.expectEqualStrings("", requestTarget("FOO\r\n\r\n"));
}
