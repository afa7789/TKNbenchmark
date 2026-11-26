//! notes: a small HTTP notes store backed by SQLite.
//!
//! Usage: NOTES_DB=<path> notes <port>

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Store = @import("Store.zig");
const api = @import("api.zig");

/// Largest request body accepted.
const max_body_len = 16 * 1024 * 1024;

const Server = struct {
    gpa: Allocator,
    io: Io,
    store: *Store,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        std.log.err("usage: {s} <port>", .{if (args.len > 0) args[0] else "notes"});
        std.process.exit(2);
    }
    const port = std.fmt.parseInt(u16, args[1], 10) catch {
        std.log.err("invalid port: {s}", .{args[1]});
        std.process.exit(2);
    };

    const db_path = try arena.dupeZ(u8, init.environ_map.get("NOTES_DB") orelse "notes.db");
    var store = try Store.open(io, db_path);
    defer store.close();

    const address = try Io.net.IpAddress.parse("127.0.0.1", port);
    var listener = try address.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);

    var server: Server = .{ .gpa = gpa, .io = io, .store = &store };
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| {
            std.log.err("accept failed: {t}", .{err});
            continue;
        };
        group.concurrent(io, serveConnection, .{ &server, stream }) catch {
            // No spare thread: serve it on this one rather than dropping it.
            serveConnection(&server, stream);
        };
    }
}

fn serveConnection(server: *Server, stream: Io.net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    var recv_buffer: [8 * 1024]u8 = undefined;
    var send_buffer: [8 * 1024]u8 = undefined;
    var conn_reader = stream.reader(io, &recv_buffer);
    var conn_writer = stream.writer(io, &send_buffer);
    var http_server = std.http.Server.init(&conn_reader.interface, &conn_writer.interface);

    var arena_state: std.heap.ArenaAllocator = .init(server.gpa);
    defer arena_state.deinit();

    while (http_server.reader.state == .ready) {
        _ = arena_state.reset(.retain_capacity);
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.log.debug("closing connection: {t}", .{err});
                return;
            },
        };
        serveRequest(server, arena_state.allocator(), &request) catch |err| {
            std.log.err("{s} {s}: {t}", .{ @tagName(request.head.method), request.head.target, err });
            return;
        };
    }
}

fn serveRequest(server: *Server, arena: Allocator, request: *std.http.Server.Request) !void {
    const method = request.head.method;
    // Reading the body invalidates the strings in `request.head`.
    const target = try arena.dupe(u8, request.head.target);

    var body: []const u8 = "";
    if (method.requestHasBody()) {
        // HTTP/1.1: a request without Content-Length or Transfer-Encoding has no body.
        if (request.head.content_length == null and request.head.transfer_encoding == .none)
            request.head.content_length = 0;
        const reader = try request.readerExpectContinue(&.{});
        body = reader.allocRemaining(arena, .limited(max_body_len)) catch |err| switch (err) {
            error.StreamTooLong => return respond(request, .{
                .status = .payload_too_large,
                .body = "{\"error\":\"body too large\"}",
            }),
            else => |e| return e,
        };
    }

    const response = api.handle(server.store, arena, .{ .method = method, .target = target, .body = body }) catch |err| blk: {
        std.log.err("{s} {s}: {t}", .{ @tagName(method), target, err });
        break :blk api.Response{ .status = .internal_server_error, .body = "{\"error\":\"internal error\"}" };
    };
    try respond(request, response);
}

fn respond(request: *std.http.Server.Request, response: api.Response) !void {
    const headers: []const std.http.Header = &.{.{ .name = "content-type", .value = response.content_type }};
    try request.respond(response.body, .{
        .status = response.status,
        .extra_headers = if (response.status == .no_content) &.{} else headers,
    });
}

test {
    _ = @import("sqlite.zig");
    _ = @import("note.zig");
    _ = @import("Store.zig");
    _ = @import("api.zig");
}
