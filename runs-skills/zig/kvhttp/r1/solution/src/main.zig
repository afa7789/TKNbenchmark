//! kvhttp: an HTTP/1.1 in-memory key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port>)

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const route = @import("route.zig");

const log = std.log.scoped(.kvhttp);

pub const max_value_len = 1 << 20;
const recv_buffer_len = 16 * 1024;
const send_buffer_len = 16 * 1024;

const App = struct {
    io: Io,
    gpa: Allocator,
    store: Store,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) std.process.fatal("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
    const port = std.fmt.parseInt(u16, args[1], 10) catch
        std.process.fatal("invalid port: {s}", .{args[1]});

    const address = try net.IpAddress.parse("127.0.0.1", port);
    var listener = address.listen(io, .{ .reuse_address = true }) catch |err|
        std.process.fatal("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer listener.deinit(io);

    var app: App = .{ .io = io, .gpa = gpa, .store = .init(gpa) };
    defer app.store.deinit();

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            error.ConnectionAborted, error.WouldBlock => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                log.warn("accept: {t}; backing off", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => return err,
        };
        group.concurrent(io, handleConnection, .{ &app, stream }) catch {
            // No thread available: serve inline rather than dropping the client.
            handleConnection(&app, stream);
        };
    }
}

fn handleConnection(app: *App, stream: net.Stream) void {
    defer stream.close(app.io);

    var recv_buffer: [recv_buffer_len]u8 = undefined;
    var send_buffer: [send_buffer_len]u8 = undefined;
    var stream_reader = stream.reader(app.io, &recv_buffer);
    var stream_writer = stream.writer(app.io, &send_buffer);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    serveRequest(app, &server) catch |err| switch (err) {
        error.HttpConnectionClosing => {},
        else => log.debug("connection error: {t}", .{err}),
    };
}

fn serveRequest(app: *App, server: *http.Server) !void {
    const head_buffer = try server.reader.receiveHead();

    // std.http.Method only knows the standard methods. Unknown methods still
    // deserve a routed response (405/404/400), so parse such a head with a
    // placeholder method that keeps body framing intact, and route with null.
    var substitute: [recv_buffer_len + 8]u8 = undefined;
    var method_known = true;
    const head = http.Server.Request.Head.parse(head_buffer) catch |err| switch (err) {
        error.UnknownHttpMethod => blk: {
            method_known = false;
            const placeholder = "PUT";
            const sp = std.mem.findScalar(u8, head_buffer, ' ') orelse unreachable; // checked by parse
            const len = placeholder.len + head_buffer.len - sp;
            @memcpy(substitute[0..placeholder.len], placeholder);
            @memcpy(substitute[placeholder.len..len], head_buffer[sp..]);
            break :blk http.Server.Request.Head.parse(substitute[0..len]) catch
                return sendStatus(server, .bad_request);
        },
        else => return sendStatus(server, .bad_request),
    };
    var request: http.Server.Request = .{ .server = server, .head_buffer = head_buffer, .head = head };
    const method: ?http.Method = if (method_known) head.method else null;
    const resolved = route.resolve(method, request.head.target);

    switch (resolved) {
        .health => try respond(&request, .ok, "ok", null),
        .list => try respondList(app, &request),
        .get => |key| {
            const value = try app.store.getCopy(app.io, app.gpa, key.slice()) orelse
                return respondDrain(&request, .not_found);
            defer app.gpa.free(value);
            try respondBodyDrain(&request, .ok, value);
        },
        .delete => |key| {
            const status: http.Status = if (app.store.remove(app.io, key.slice())) .no_content else .not_found;
            try respondDrain(&request, status);
        },
        .put => |key| try handlePut(app, &request, key.slice()),
        .err => |status| try respondDrain(&request, status),
    }
}

fn handlePut(app: *App, request: *http.Server.Request, key: []const u8) !void {
    if (request.head.content_length) |len| {
        if (len > max_value_len) return respond(request, .payload_too_large, "", null);
    }
    const value = readBody(app.gpa, request) catch |err| switch (err) {
        error.StreamTooLong => return respond(request, .payload_too_large, "", null),
        else => return err,
    };
    errdefer app.gpa.free(value);
    const status: http.Status = switch (try app.store.putOwned(app.io, key, value)) {
        .created => .created,
        .replaced => .ok,
    };
    try respond(request, status, "", null);
}

fn readBody(gpa: Allocator, request: *http.Server.Request) ![]u8 {
    if (request.head.content_length == null and request.head.transfer_encoding == .none)
        return gpa.alloc(u8, 0);
    var transfer_buffer: [64]u8 = undefined;
    const content_length = request.head.content_length;
    const body = try request.readerExpectContinue(&transfer_buffer);
    if (content_length) |len| {
        // Caller has already rejected lengths above max_value_len.
        const value = try gpa.alloc(u8, @intCast(len));
        errdefer gpa.free(value);
        try body.readSliceAll(value);
        return value;
    }
    // Chunked: the limit is exclusive (reaching it is an error), hence + 1.
    return body.allocRemaining(gpa, .limited(max_value_len + 1));
}

fn respondList(app: *App, request: *http.Server.Request) !void {
    const keys = try app.store.sortedKeys(app.io, app.gpa);
    defer Store.freeKeys(app.gpa, keys);

    var json: Io.Writer.Allocating = .init(app.gpa);
    defer json.deinit();
    try std.json.Stringify.value(keys, .{}, &json.writer);
    try respond(request, .ok, json.written(), "application/json");
}

/// Discards any request body (so closing the socket doesn't reset the
/// connection before the client reads the response), then responds.
fn respondDrain(request: *http.Server.Request, status: http.Status) !void {
    try respondBodyDrain(request, status, "");
}

fn respondBodyDrain(request: *http.Server.Request, status: http.Status, body: []const u8) !void {
    try discardBody(request);
    try respond(request, status, body, null);
}

fn discardBody(request: *http.Server.Request) !void {
    if (!request.head.method.requestHasBody()) return;
    if (request.head.content_length == null and request.head.transfer_encoding == .none) return;
    if ((request.head.content_length orelse 0) > max_value_len) return;
    var transfer_buffer: [64]u8 = undefined;
    const body = try request.readerExpectContinue(&transfer_buffer);
    _ = try body.discardRemaining();
}

fn respond(
    request: *http.Server.Request,
    status: http.Status,
    body: []const u8,
    content_type: ?[]const u8,
) !void {
    const headers: []const http.Header = if (content_type) |ct|
        &.{.{ .name = "content-type", .value = ct }}
    else
        &.{};
    try request.respond(body, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = headers,
    });
}

fn sendStatus(server: *http.Server, status: http.Status) !void {
    try server.out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-length: 0\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try server.out.flush();
}

test {
    _ = Store;
    _ = route;
}
