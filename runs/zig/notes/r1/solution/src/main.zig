//! notes: a small HTTP notes service backed by SQLite.
//!
//! Usage: NOTES_DB=<path> notes <port>

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Store = @import("Store.zig");
const api = @import("api.zig");

const log = std.log.scoped(.notes);

/// Largest request body accepted; larger bodies are rejected with 413.
const max_body_len = 32 * 1024 * 1024;
/// Also bounds the size of the request head.
const recv_buffer_len = 64 * 1024;
const send_buffer_len = 16 * 1024;

const App = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        log.err("usage: {s} <port>", .{if (args.len > 0) args[0] else "notes"});
        return error.InvalidArguments;
    }
    const port = std.fmt.parseInt(u16, args[1], 10) catch {
        log.err("invalid port: {s}", .{args[1]});
        return error.InvalidArguments;
    };
    const db_path = init.environ_map.get("NOTES_DB") orelse {
        log.err("the NOTES_DB environment variable must name the database file", .{});
        return error.MissingDatabasePath;
    };

    var store = try Store.open(io, try arena.dupeZ(u8, db_path));
    defer store.close();

    const address = try Io.net.IpAddress.parseIp4("127.0.0.1", port);
    var server = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer server.deinit(io);

    const app: App = .{ .io = io, .gpa = init.gpa, .store = &store };

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => return,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, serveConnection, .{ &app, stream }) catch {
            // No spare unit of concurrency: serve on this thread instead.
            serveConnection(&app, stream);
        };
    }
}

fn serveConnection(app: *const App, stream: Io.net.Stream) void {
    const io = app.io;
    defer stream.close(io);

    var recv_buffer: [recv_buffer_len]u8 = undefined;
    var send_buffer: [send_buffer_len]u8 = undefined;
    var reader = stream.reader(io, &recv_buffer);
    var writer = stream.writer(io, &send_buffer);
    var http: std.http.Server = .init(&reader.interface, &writer.interface);

    var arena_state: std.heap.ArenaAllocator = .init(app.gpa);
    defer arena_state.deinit();

    while (true) {
        _ = arena_state.reset(.retain_capacity);
        var request = http.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                log.debug("receiving request head failed: {t}", .{err});
                return;
            },
        };
        serveRequest(app, arena_state.allocator(), &request) catch |err| {
            log.debug("serving request failed: {t}", .{err});
            return;
        };
        if (!request.head.keep_alive) return;
    }
}

fn serveRequest(app: *const App, arena: Allocator, request: *std.http.Server.Request) !void {
    const method = request.head.method;
    // Reading the body invalidates the strings of the request head.
    const target = try arena.dupe(u8, request.head.target);
    const keep_alive = request.head.keep_alive;

    const body = readBody(arena, request) catch |err| switch (err) {
        error.StreamTooLong => return respond(request, .{
            .status = .payload_too_large,
            .body = "{\"error\":\"request body too large\"}",
        }, false),
        else => return err,
    };

    const response = api.handle(app.store, arena, .{
        .method = method,
        .target = target,
        .body = body,
    }) catch |err| blk: {
        log.err("{s} {s}: {t}", .{ @tagName(method), target, err });
        break :blk api.Response{
            .status = .internal_server_error,
            .body = "{\"error\":\"internal server error\"}",
        };
    };
    try respond(request, response, keep_alive);
}

fn readBody(arena: Allocator, request: *std.http.Server.Request) ![]const u8 {
    const head = &request.head;
    if (!head.method.requestHasBody()) return "";
    // Without a length or chunked encoding, a request has no body; say so
    // explicitly, since `std.http.Server` would otherwise read until EOF.
    if (head.content_length == null and head.transfer_encoding == .none) head.content_length = 0;
    const body_reader = try request.readerExpectContinue(&.{});
    return body_reader.allocRemaining(arena, .limited(max_body_len)) catch |err| switch (err) {
        error.ReadFailed => request.server.reader.body_err orelse error.ReadFailed,
        else => |e| e,
    };
}

fn respond(request: *std.http.Server.Request, response: api.Response, keep_alive: bool) !void {
    try request.respond(response.body, .{
        .status = response.status,
        .keep_alive = keep_alive,
        .extra_headers = &.{.{ .name = "content-type", .value = response.content_type }},
    });
}

test {
    _ = @import("sqlite.zig");
    _ = @import("validate.zig");
    _ = @import("Store.zig");
    _ = @import("api.zig");
}
