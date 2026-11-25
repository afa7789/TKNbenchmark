//! kvhttp: an HTTP/1.1 in-memory key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port>)

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

pub const std_options: std.Options = .{ .log_level = .warn };

const max_key_len = 64;
const max_value_len = 1 << 20;
/// Upper bound on request bytes we are willing to read and throw away so that
/// closing the socket does not reset the connection before the client reads
/// our response.
const max_drain_len = 8 << 20;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) std.process.fatal("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
    const port = std.fmt.parseInt(u16, args[1], 10) catch
        std.process.fatal("invalid port: {s}", .{args[1]});

    const address = try net.IpAddress.parse("127.0.0.1", port);
    var listener = address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }) catch |err|
        std.process.fatal("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer listener.deinit(io);

    var store: Store = .init(gpa);
    defer store.deinit();

    var app: App = .{ .io = io, .gpa = gpa, .store = &store };
    try app.serve(&listener);
}

const App = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,

    fn serve(app: *App, listener: *net.Server) !void {
        const io = app.io;
        var group: Io.Group = .init;
        defer group.cancel(io);

        while (true) {
            const stream = listener.accept(io) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.ConnectionAborted, error.WouldBlock => continue,
                else => {
                    log.warn("accept failed: {t}", .{err});
                    // Back off briefly, e.g. when out of file descriptors.
                    try io.sleep(.fromMilliseconds(10), .awake);
                    continue;
                },
            };
            group.concurrent(io, handleConnection, .{ app, stream }) catch {
                // No thread available: serve inline rather than drop the client.
                handleConnection(app, stream);
            };
        }
    }

    fn handleConnection(app: *App, stream: net.Stream) void {
        defer stream.close(app.io);
        app.handleRequest(stream) catch |err| switch (err) {
            error.ReadFailed, error.WriteFailed => {},
            else => log.debug("request failed: {t}", .{err}),
        };
    }

    fn handleRequest(app: *App, stream: net.Stream) !void {
        const io = app.io;
        var in_buf: [16 * 1024]u8 = undefined;
        var out_buf: [16 * 1024]u8 = undefined;
        var stream_reader = stream.reader(io, &in_buf);
        var stream_writer = stream.writer(io, &out_buf);
        const out = &stream_writer.interface;
        var server: http.Server = .init(&stream_reader.interface, out);

        const head_buffer = server.reader.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing, error.ReadFailed => return,
            error.HttpHeadersOversize => return writeBare(out, .request_header_fields_too_large),
            error.HttpRequestTruncated => return writeBare(out, .bad_request),
        };

        const head = http.Server.Request.Head.parse(head_buffer) catch |err| switch (err) {
            // Methods std.http does not know (e.g. "PROPFIND") still deserve
            // a proper 404/405/400 based on the path.
            error.UnknownHttpMethod => {
                drainContentLength(&server, head_buffer);
                return writeBare(out, statusForUnknownMethod(head_buffer));
            },
            else => return writeBare(out, .bad_request),
        };

        var request: http.Server.Request = .{ .server = &server, .head = head, .head_buffer = head_buffer };
        const route: Route = .parse(head.target);

        // Copy the key: reading the body invalidates strings in the head.
        var key_buf: [max_key_len]u8 = undefined;
        const key: []const u8 = switch (route) {
            .item => |k| blk: {
                @memcpy(key_buf[0..k.len], k);
                break :blk key_buf[0..k.len];
            },
            else => "",
        };

        const method = head.method;
        const status: http.Status = switch (route) {
            .not_found => .not_found,
            .bad_key => .bad_request,
            .health => if (method == .GET)
                return respond(&request, .ok, "ok", &.{.{ .name = "content-type", .value = "text/plain" }})
            else
                .method_not_allowed,
            .list => if (method == .GET) return app.respondList(&request) else .method_not_allowed,
            .item => switch (method) {
                .GET => return app.respondGet(&request, key),
                .PUT => return app.respondPut(&request, key),
                .DELETE => if (app.store.remove(io, key)) .no_content else .not_found,
                else => .method_not_allowed,
            },
        };
        return respond(&request, status, "", &.{});
    }

    fn respondGet(app: *App, request: *http.Server.Request, key: []const u8) !void {
        const value = try app.store.getCopy(app.io, app.gpa, key) orelse
            return respond(request, .not_found, "", &.{});
        defer app.gpa.free(value);
        return respond(request, .ok, value, &.{.{ .name = "content-type", .value = "application/octet-stream" }});
    }

    fn respondPut(app: *App, request: *http.Server.Request, key: []const u8) !void {
        if (request.head.content_length) |len| if (len > max_value_len)
            return respond(request, .payload_too_large, "", &.{});

        const body_reader = request.readerExpectContinue(&.{}) catch |err| switch (err) {
            error.HttpExpectationFailed => return respond(request, .expectation_failed, "", &.{}),
            error.WriteFailed => return error.WriteFailed,
        };
        const value = body_reader.allocRemaining(app.gpa, .limited(max_value_len + 1)) catch |err| switch (err) {
            error.StreamTooLong => {
                _ = body_reader.discard(.limited(max_drain_len)) catch {};
                return respond(request, .payload_too_large, "", &.{});
            },
            error.ReadFailed => {
                if (bodyErrorStatus(request)) |status| return respond(request, status, "", &.{});
                return error.ReadFailed;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        const result = app.store.putOwned(app.io, key, value) catch |err| {
            app.gpa.free(value);
            return err;
        };
        return respond(request, switch (result) {
            .created => .created,
            .replaced => .ok,
        }, "", &.{});
    }

    fn respondList(app: *App, request: *http.Server.Request) !void {
        const keys = try app.store.sortedKeys(app.io, app.gpa);
        defer Store.freeKeys(app.gpa, keys);

        var json: Io.Writer.Allocating = .init(app.gpa);
        defer json.deinit();
        try std.json.Stringify.value(keys, .{}, &json.writer);
        return respond(request, .ok, json.written(), &.{.{ .name = "content-type", .value = "application/json" }});
    }
};

/// Returns a status for a malformed request body (e.g. bad chunk encoding),
/// or null if the failure came from the socket itself.
fn bodyErrorStatus(request: *http.Server.Request) ?http.Status {
    return if (request.server.reader.body_err != null) .bad_request else null;
}

fn respond(
    request: *http.Server.Request,
    status: http.Status,
    body: []const u8,
    extra_headers: []const http.Header,
) !void {
    // Bodies sent with methods that normally have none (e.g. GET) are not
    // read by std.http; drain them so closing the socket does not send RST.
    if (!request.head.method.requestHasBody() and request.server.reader.state == .received_head)
        drainContentLength(request.server, request.head_buffer);

    request.respond(body, .{
        .status = status,
        .keep_alive = false,
        .extra_headers = extra_headers,
    }) catch |err| switch (err) {
        error.HttpExpectationFailed => return writeBare(request.server.out, .expectation_failed),
        error.WriteFailed => return error.WriteFailed,
    };
}

/// Writes a minimal response with an empty body and closes the exchange.
fn writeBare(out: *Io.Writer, status: http.Status) Io.Writer.Error!void {
    try out.print("HTTP/1.1 {d} {s}\r\ncontent-length: 0\r\nconnection: close\r\n\r\n", .{
        @intFromEnum(status), status.phrase() orelse "",
    });
    try out.flush();
}

/// Discards a `Content-Length` body that std.http would not read itself.
fn drainContentLength(server: *http.Server, head_buffer: []const u8) void {
    const len = contentLength(head_buffer) orelse return;
    if (len > max_drain_len) return;
    server.reader.in.discardAll64(len) catch {};
}

fn contentLength(head_buffer: []const u8) ?u64 {
    var it: http.HeaderIterator = .init(head_buffer);
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "content-length"))
            return std.fmt.parseInt(u64, std.mem.trim(u8, header.value, " \t"), 10) catch null;
    }
    return null;
}

fn statusForUnknownMethod(head_buffer: []const u8) http.Status {
    const line_end = std.mem.indexOf(u8, head_buffer, "\r\n") orelse return .bad_request;
    var parts = std.mem.splitScalar(u8, head_buffer[0..line_end], ' ');
    _ = parts.next();
    const target = parts.next() orelse return .bad_request;
    return switch (Route.parse(target)) {
        .not_found => .not_found,
        .bad_key => .bad_request,
        .health, .list, .item => .method_not_allowed,
    };
}

const Route = union(enum) {
    health,
    list,
    item: []const u8,
    bad_key,
    not_found,

    fn parse(target: []const u8) Route {
        if (std.mem.eql(u8, target, "/health")) return .health;
        if (std.mem.eql(u8, target, "/kv")) return .list;
        const prefix = "/kv/";
        if (std.mem.startsWith(u8, target, prefix)) {
            const key = target[prefix.len..];
            return if (isValidKey(key)) .{ .item = key } else .bad_key;
        }
        return .not_found;
    }
};

fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

test "route parsing" {
    const t = std.testing;
    try t.expectEqual(Route.health, Route.parse("/health"));
    try t.expectEqual(Route.list, Route.parse("/kv"));
    try t.expectEqualStrings("a-B_9", Route.parse("/kv/a-B_9").item);
    try t.expectEqual(Route.bad_key, Route.parse("/kv/"));
    try t.expectEqual(Route.bad_key, Route.parse("/kv/a/b"));
    try t.expectEqual(Route.bad_key, Route.parse("/kv/bad.key"));
    try t.expectEqual(Route.bad_key, Route.parse("/kv/" ++ "x" ** 65));
    try t.expectEqualStrings("x" ** 64, Route.parse("/kv/" ++ "x" ** 64).item);
    try t.expectEqual(Route.not_found, Route.parse("/"));
    try t.expectEqual(Route.not_found, Route.parse("/health/"));
    try t.expectEqual(Route.not_found, Route.parse("/kvx"));
}

test "unknown method status" {
    const t = std.testing;
    try t.expectEqual(http.Status.method_not_allowed, statusForUnknownMethod("FOO /health HTTP/1.1\r\n\r\n"));
    try t.expectEqual(http.Status.not_found, statusForUnknownMethod("FOO /x HTTP/1.1\r\n\r\n"));
    try t.expectEqual(http.Status.bad_request, statusForUnknownMethod("FOO /kv/a.b HTTP/1.1\r\n\r\n"));
}

test "content length lookup" {
    try std.testing.expectEqual(@as(?u64, 12), contentLength("GET / HTTP/1.1\r\nContent-Length: 12\r\n\r\n"));
    try std.testing.expectEqual(@as(?u64, null), contentLength("GET / HTTP/1.1\r\nHost: x\r\n\r\n"));
}

test {
    _ = Store;
}
