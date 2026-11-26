//! notes: a small JSON notes store over HTTP, backed by SQLite.
//!
//! Usage: NOTES_DB=<path> notes <port>

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const http = std.http;

const api = @import("api.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.notes);

/// Largest request body accepted; bigger ones get 413.
const max_body_len = 16 * 1024 * 1024;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const port_arg = args.next() orelse return usage();
    const port = std.fmt.parseInt(u16, port_arg, 10) catch return usage();

    const db_path = init.environ_map.get("NOTES_DB") orelse {
        log.err("the NOTES_DB environment variable must name the database file", .{});
        return 2;
    };
    const db_path_z = try init.arena.allocator().dupeZ(u8, db_path);

    var store: Store = try .open(io, db_path_z);
    defer store.close();

    const address: Io.net.IpAddress = try .parseIp4("127.0.0.1", port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    log.info("listening on 127.0.0.1:{d}", .{port});

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            error.ConnectionAborted => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        const conn: Connection = .{ .io = io, .gpa = gpa, .store = &store, .stream = stream };
        group.concurrent(io, Connection.serve, .{conn}) catch {
            // No capacity for another task: serve this connection inline.
            conn.serve();
        };
    }
}

fn usage() u8 {
    std.debug.print("usage: NOTES_DB=<path> notes <port>\n", .{});
    return 2;
}

const Connection = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
    stream: Io.net.Stream,

    fn serve(conn: Connection) void {
        defer conn.stream.close(conn.io);

        var recv_buffer: [16 * 1024]u8 = undefined;
        var send_buffer: [16 * 1024]u8 = undefined;
        var reader = conn.stream.reader(conn.io, &recv_buffer);
        var writer = conn.stream.writer(conn.io, &send_buffer);
        var server: http.Server = .init(&reader.interface, &writer.interface);

        var arena: std.heap.ArenaAllocator = .init(conn.gpa);
        defer arena.deinit();

        while (true) {
            _ = arena.reset(.retain_capacity);
            var request = server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                error.HttpHeadersInvalid => return rejectHead(&writer.interface, "400 Bad Request"),
                error.HttpHeadersOversize => return rejectHead(&writer.interface, "431 Request Header Fields Too Large"),
                else => {
                    log.debug("receive head failed: {t}", .{err});
                    return;
                },
            };
            conn.handleRequest(arena.allocator(), &request) catch |err| {
                log.debug("request failed: {t}", .{err});
                return;
            };
            if (!request.head.keep_alive) return;
        }
    }

    /// Answers a request whose head could not be parsed, then gives up on the connection.
    fn rejectHead(out: *Io.Writer, comptime status: []const u8) void {
        out.writeAll("HTTP/1.1 " ++ status ++ "\r\nconnection: close\r\ncontent-length: 0\r\n\r\n") catch return;
        out.flush() catch {};
    }

    fn handleRequest(conn: Connection, arena: Allocator, request: *http.Server.Request) !void {
        const method = request.head.method;
        // The target string is invalidated once the body is read.
        const target = try arena.dupe(u8, request.head.target);

        // Without a length or chunked encoding, a request has no body (RFC 9112,
        // section 6.3). std.http.Server asserts one of them is set for methods
        // that may carry a body, so make the empty length explicit.
        if (request.head.content_length == null and request.head.transfer_encoding == .none) {
            request.head.content_length = 0;
        }

        var body: []const u8 = "";
        if (method.requestHasBody()) {
            if (request.head.content_length) |len| if (len > max_body_len) {
                return respond(request, .{
                    .status = .payload_too_large,
                    .body = "{\"error\":\"request body too large\"}",
                });
            };
            const body_reader = try request.readerExpectContinue(&.{});
            body = body_reader.allocRemaining(arena, .limited(max_body_len)) catch |err| switch (err) {
                error.StreamTooLong => return respond(request, .{
                    .status = .payload_too_large,
                    .body = "{\"error\":\"request body too large\"}",
                }),
                else => |e| return e,
            };
        }

        const response = try api.handle(conn.store, arena, .{ .method = method, .target = target, .body = body });
        try respond(request, response);
    }

    fn respond(request: *http.Server.Request, response: api.Response) !void {
        var headers_buf: [2]http.Header = undefined;
        var headers: std.ArrayList(http.Header) = .initBuffer(&headers_buf);
        if (response.status != .no_content) {
            headers.appendAssumeCapacity(.{ .name = "content-type", .value = response.content_type });
        }
        if (response.allow) |allow| headers.appendAssumeCapacity(.{ .name = "allow", .value = allow });
        try request.respond(response.body, .{ .status = response.status, .extra_headers = headers.items });
    }
};

test {
    _ = @import("sqlite.zig");
    _ = @import("note.zig");
    _ = @import("Store.zig");
    _ = @import("api.zig");
}
