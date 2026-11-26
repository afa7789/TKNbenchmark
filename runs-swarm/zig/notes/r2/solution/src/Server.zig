//! HTTP/1.1 server: accepts connections, runs each one concurrently, reads
//! requests and hands them to `router.dispatch`.

const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const Allocator = std.mem.Allocator;
const Store = @import("Store.zig");
const router = @import("router.zig");
const web = @import("web.zig");

const log = std.log.scoped(.server);

const Server = @This();

gpa: Allocator,
io: Io,
store: *Store,
options: Options,

pub const Options = struct {
    /// Larger request bodies are answered with 413.
    max_body_len: usize = 1024 * 1024,
    /// Also the maximum size of a request head; larger heads get 431.
    read_buffer_len: usize = 16 * 1024,
    write_buffer_len: usize = 16 * 1024,
};

/// Accepts connections on `address` until the task is canceled.
pub fn serve(server: *Server, address: net.IpAddress) !void {
    const io = server.io;
    var listener = try address.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);
    log.info("listening on {f}", .{address});

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => {
                log.err("accept: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, handleConnection, .{ server, stream }) catch |err| {
            log.warn("serving connection inline: {t}", .{err});
            handleConnection(server, stream);
        };
    }
}

fn handleConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    const read_buffer = server.gpa.alloc(u8, server.options.read_buffer_len) catch return;
    defer server.gpa.free(read_buffer);
    const write_buffer = server.gpa.alloc(u8, server.options.write_buffer_len) catch return;
    defer server.gpa.free(write_buffer);

    var stream_reader = stream.reader(io, read_buffer);
    var stream_writer = stream.writer(io, write_buffer);
    var http: std.http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    var arena: std.heap.ArenaAllocator = .init(server.gpa);
    defer arena.deinit();

    while (true) {
        _ = arena.reset(.{ .retain_with_limit = 64 * 1024 });

        var request = http.receiveHead() catch |err| {
            switch (err) {
                error.HttpConnectionClosing, error.ReadFailed => {},
                error.HttpHeadersOversize => respondRaw(&stream_writer.interface, "431 Request Header Fields Too Large"),
                error.HttpHeadersInvalid, error.HttpRequestTruncated => respondRaw(&stream_writer.interface, "400 Bad Request"),
            }
            return;
        };
        const keep_alive = server.handleRequest(&request, arena.allocator()) catch |err| {
            log.debug("connection closed: {t}", .{err});
            return;
        };
        if (!keep_alive) return;
    }
}

/// Answers one request. Returns whether the connection can serve another.
fn handleRequest(server: *Server, request: *std.http.Server.Request, arena: Allocator) !bool {
    const head = request.head;
    // The head's strings live in the read buffer, which reading the body reuses.
    const target = try arena.dupe(u8, head.target);
    const path, const query = splitTarget(target);

    var keep_alive = head.keep_alive;
    var body: []const u8 = "";
    // A request without Content-Length or chunked encoding has no body (RFC 9112,
    // section 6.3); reading one anyway would wait for the client to close. The
    // std server cannot resume such a connection, so it is closed after the response.
    const has_body = head.content_length != null or head.transfer_encoding == .chunked;
    if (head.method.requestHasBody() and !has_body) {
        keep_alive = false;
    } else if (head.method.requestHasBody()) {
        if (head.content_length) |len| if (len > server.options.max_body_len) {
            try respond(request, try tooLarge(arena), false);
            return false;
        };
        const reader = request.readerExpectContinue(&.{}) catch |err| switch (err) {
            error.HttpExpectationFailed => {
                try respond(request, try web.jsonError(arena, .expectation_failed, "unsupported Expect header"), false);
                return false;
            },
            else => |e| return e,
        };
        body = reader.allocRemaining(arena, .limited(server.options.max_body_len + 1)) catch |err| switch (err) {
            error.StreamTooLong => {
                try respond(request, try tooLarge(arena), false);
                return false;
            },
            error.ReadFailed, error.OutOfMemory => |e| return e,
        };
        if (body.len > server.options.max_body_len) {
            try respond(request, try tooLarge(arena), false);
            return false;
        }
    }

    var req: web.Request = .{
        .arena = arena,
        .store = server.store,
        .method = head.method,
        .path = path,
        .query = query,
        .body = body,
    };
    const res = router.dispatch(&req) catch |err| blk: {
        log.err("{t} {s}: {t}", .{ head.method, path, err });
        if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
        keep_alive = false;
        break :blk try web.jsonError(arena, .internal_server_error, "internal error");
    };
    try respond(request, res, keep_alive);
    return keep_alive;
}

fn respond(request: *std.http.Server.Request, res: web.Response, keep_alive: bool) !void {
    var headers: [2]std.http.Header = undefined;
    var len: usize = 0;
    if (res.content_type) |value| {
        headers[len] = .{ .name = "content-type", .value = value };
        len += 1;
    }
    if (res.allow) |value| {
        headers[len] = .{ .name = "allow", .value = value };
        len += 1;
    }
    try request.respond(res.body, .{
        .status = res.status,
        .keep_alive = keep_alive,
        .extra_headers = headers[0..len],
    });
}

fn tooLarge(arena: Allocator) !web.Response {
    return web.jsonError(arena, .payload_too_large, "request body too large");
}

/// Best effort response for requests that could not be parsed.
fn respondRaw(out: *Io.Writer, status_line: []const u8) void {
    out.print("HTTP/1.1 {s}\r\nconnection: close\r\ncontent-length: 0\r\n\r\n", .{status_line}) catch return;
    out.flush() catch return;
}

/// Splits a request target into its path and query string.
fn splitTarget(target: []const u8) struct { []const u8, []const u8 } {
    const without_fragment = target[0 .. std.mem.indexOfScalar(u8, target, '#') orelse target.len];
    const q = std.mem.indexOfScalar(u8, without_fragment, '?') orelse return .{ without_fragment, "" };
    return .{ without_fragment[0..q], without_fragment[q + 1 ..] };
}

test splitTarget {
    const path, const query = splitTarget("/notes?tag=a&q=b");
    try std.testing.expectEqualStrings("/notes", path);
    try std.testing.expectEqualStrings("tag=a&q=b", query);

    const path2, const query2 = splitTarget("/health");
    try std.testing.expectEqualStrings("/health", path2);
    try std.testing.expectEqualStrings("", query2);
}
