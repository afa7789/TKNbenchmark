//! HTTP front end for the key-value store: one request per connection, each
//! connection served on its own task.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const mem = std.mem;
const Allocator = mem.Allocator;

const Store = @import("Store.zig");
const request = @import("request.zig");

const Server = @This();

pub const max_value_bytes = 1024 * 1024;
pub const max_key_len = 64;
/// Upper bound on the request head; larger heads get `431`.
const max_head_bytes = 16 * 1024;
/// Unread request bodies up to this size are discarded before responding so
/// the client sees the response instead of a connection reset.
const max_discard_bytes = 8 * 1024 * 1024;
const kv_prefix = "/kv/";

io: Io,
gpa: Allocator,
store: *Store,

/// Accepts connections forever, serving each concurrently.
pub fn serve(server: *Server, listener: *net.Server) !void {
    var group: Io.Group = .init;
    defer group.cancel(server.io);

    while (true) {
        const stream = listener.accept(server.io) catch |err| switch (err) {
            error.ConnectionAborted => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                std.log.warn("accept: {t}; backing off", .{err});
                server.io.sleep(.fromMilliseconds(10), .awake) catch {};
                continue;
            },
            else => |e| return e,
        };
        group.concurrent(server.io, handleConnection, .{ server, stream }) catch {
            // No worker available: serve inline rather than dropping the client.
            handleConnection(server, stream);
        };
    }
}

fn handleConnection(server: *Server, stream: net.Stream) void {
    defer stream.close(server.io);

    var recv_buffer: [max_head_bytes]u8 = undefined;
    var send_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(server.io, &recv_buffer);
    var stream_writer = stream.writer(server.io, &send_buffer);

    var conn: Connection = .{
        .server = server,
        .out = &stream_writer.interface,
        .reader = .{
            .in = &stream_reader.interface,
            .state = .ready,
            .interface = undefined,
            .max_head_len = recv_buffer.len,
        },
    };
    conn.serveOne() catch |err| switch (err) {
        // The peer went away or misbehaved; there is nobody left to tell.
        error.ReadFailed, error.WriteFailed => {},
    };
}

/// Where a request is dispatched, determined from its method and path alone.
pub const Route = union(enum) {
    health,
    list,
    get: []const u8,
    put: []const u8,
    delete: []const u8,
    bad_key,
    not_found,
    /// Carries the value of the `Allow` header.
    method_not_allowed: []const u8,
};

pub fn route(method: []const u8, path: []const u8) Route {
    if (mem.eql(u8, path, "/health")) {
        return if (mem.eql(u8, method, "GET")) .health else .{ .method_not_allowed = "GET" };
    }
    if (mem.eql(u8, path, "/kv")) {
        return if (mem.eql(u8, method, "GET")) .list else .{ .method_not_allowed = "GET" };
    }
    if (mem.startsWith(u8, path, kv_prefix)) {
        const key = path[kv_prefix.len..];
        if (!isValidKey(key)) return .bad_key;
        if (mem.eql(u8, method, "GET")) return .{ .get = key };
        if (mem.eql(u8, method, "PUT")) return .{ .put = key };
        if (mem.eql(u8, method, "DELETE")) return .{ .delete = key };
        return .{ .method_not_allowed = "GET, PUT, DELETE" };
    }
    return .not_found;
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

const Response = struct {
    status: http.Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    allow: ?[]const u8 = null,
};

const Connection = struct {
    server: *Server,
    out: *Io.Writer,
    reader: http.Reader,
    /// The parsed head. Its slices are invalidated once the body is read;
    /// only the framing fields are used after that point.
    head: ?request.Head = null,
    body: ?*Io.Reader = null,
    continue_sent: bool = false,

    const Error = error{ ReadFailed, WriteFailed };

    fn serveOne(conn: *Connection) Error!void {
        const head_bytes = conn.reader.receiveHead() catch |err| switch (err) {
            error.HttpHeadersOversize => return conn.respond(.{ .status = .request_header_fields_too_large }),
            error.HttpRequestTruncated, error.HttpConnectionClosing => return,
            error.ReadFailed => return error.ReadFailed,
        };
        const head = request.parse(head_bytes) catch |err| return conn.respond(.{ .status = switch (err) {
            error.BadRequest => .bad_request,
            error.ExpectationFailed => .expectation_failed,
        } });
        conn.head = head;

        const store = conn.server.store;
        const io = conn.server.io;
        const gpa = conn.server.gpa;

        switch (route(head.method, head.path())) {
            .health => try conn.respond(.{ .status = .ok, .body = "ok", .content_type = "text/plain" }),
            .list => {
                const json = listJson(gpa, store, io) catch return conn.respond(.{ .status = .internal_server_error });
                defer gpa.free(json);
                try conn.respond(.{ .status = .ok, .body = json, .content_type = "application/json" });
            },
            .get => |key| {
                const value = store.getCopy(io, gpa, key) catch return conn.respond(.{ .status = .internal_server_error });
                if (value) |bytes| {
                    defer gpa.free(bytes);
                    try conn.respond(.{ .status = .ok, .body = bytes, .content_type = "application/octet-stream" });
                } else {
                    try conn.respond(.{ .status = .not_found });
                }
            },
            .put => |key_in_head| {
                // The head lives in the receive buffer, which reading the body may overwrite.
                var key_buffer: [max_key_len]u8 = undefined;
                const key = key_buffer[0..key_in_head.len];
                @memcpy(key, key_in_head);
                try conn.handlePut(key);
            },
            .delete => |key| try conn.respond(.{ .status = if (store.delete(io, key)) .no_content else .not_found }),
            .bad_key => try conn.respond(.{ .status = .bad_request }),
            .not_found => try conn.respond(.{ .status = .not_found }),
            .method_not_allowed => |allow| try conn.respond(.{ .status = .method_not_allowed, .allow = allow }),
        }
    }

    fn handlePut(conn: *Connection, key: []const u8) Error!void {
        const gpa = conn.server.gpa;
        const head = conn.head.?;
        if ((head.content_length orelse 0) > max_value_bytes) {
            return conn.respond(.{ .status = .payload_too_large });
        }

        const value: []u8 = if (head.hasBody()) blk: {
            const body = try conn.bodyReader();
            break :blk body.allocRemaining(gpa, .limited(max_value_bytes + 1)) catch |err| switch (err) {
                error.StreamTooLong => return conn.respond(.{ .status = .payload_too_large }),
                error.OutOfMemory => return conn.respond(.{ .status = .internal_server_error }),
                // A malformed chunked body is the client's fault; a broken socket is not reportable.
                error.ReadFailed => if (conn.reader.body_err != null)
                    return conn.respond(.{ .status = .bad_request })
                else
                    return error.ReadFailed,
            };
        } else &.{};

        const result = conn.server.store.put(conn.server.io, key, value) catch {
            gpa.free(value);
            return conn.respond(.{ .status = .internal_server_error });
        };
        try conn.respond(.{ .status = switch (result) {
            .created => .created,
            .replaced => .ok,
        } });
    }

    /// Returns the request body stream, first sending `100 Continue` if the
    /// client asked for it. Asserts the request has a body.
    fn bodyReader(conn: *Connection) Error!*Io.Reader {
        if (conn.body) |body| return body;
        const head = conn.head.?;
        if (head.expect_continue and !conn.continue_sent) {
            conn.out.writeAll("HTTP/1.1 100 Continue\r\n\r\n") catch return error.WriteFailed;
            conn.out.flush() catch return error.WriteFailed;
            conn.continue_sent = true;
        }
        const body = conn.reader.bodyReader(&.{}, if (head.chunked) .chunked else .none, head.content_length);
        conn.body = body;
        return body;
    }

    /// Writes a complete response. The connection is closed afterwards.
    fn respond(conn: *Connection, res: Response) Error!void {
        conn.discardBody();
        const out = conn.out;
        out.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(res.status), res.status.phrase() orelse "" }) catch return error.WriteFailed;
        if (res.content_type) |content_type| out.print("Content-Type: {s}\r\n", .{content_type}) catch return error.WriteFailed;
        if (res.allow) |allow| out.print("Allow: {s}\r\n", .{allow}) catch return error.WriteFailed;
        out.print("Content-Length: {d}\r\nConnection: close\r\n\r\n", .{res.body.len}) catch return error.WriteFailed;
        out.writeAll(res.body) catch return error.WriteFailed;
        out.flush() catch return error.WriteFailed;
    }

    /// Best-effort, bounded discard of any unread request body, so that
    /// closing the socket does not reset the connection before the client
    /// has read the response.
    fn discardBody(conn: *Connection) void {
        const head = conn.head orelse return;
        if (!head.hasBody()) return;
        // A client still waiting for `100 Continue` will not send the body.
        if (head.expect_continue and !conn.continue_sent) return;
        const body = conn.bodyReader() catch return;
        var remaining: usize = max_discard_bytes;
        while (remaining > 0) remaining -= body.discard(.limited(remaining)) catch return;
    }
};

fn listJson(gpa: Allocator, store: *Store, io: Io) Allocator.Error![]u8 {
    const keys = try store.keys(io, gpa);
    defer Store.freeKeys(gpa, keys);

    var json: Io.Writer.Allocating = .init(gpa);
    defer json.deinit();
    const w = &json.writer;
    // Keys are restricted to `[A-Za-z0-9_-]`, so they never need escaping.
    w.writeByte('[') catch return error.OutOfMemory;
    for (keys, 0..) |key, i| {
        if (i != 0) w.writeByte(',') catch return error.OutOfMemory;
        w.print("\"{s}\"", .{key}) catch return error.OutOfMemory;
    }
    w.writeByte(']') catch return error.OutOfMemory;
    return json.toOwnedSlice();
}

const testing = std.testing;

test route {
    try testing.expectEqual(Route.health, route("GET", "/health"));
    try testing.expectEqualStrings("GET", route("POST", "/health").method_not_allowed);
    try testing.expectEqual(Route.list, route("GET", "/kv"));
    try testing.expectEqualStrings("GET", route("DELETE", "/kv").method_not_allowed);
    try testing.expectEqualStrings("a-B_9", route("PUT", "/kv/a-B_9").put);
    try testing.expectEqualStrings("a", route("GET", "/kv/a").get);
    try testing.expectEqualStrings("a", route("DELETE", "/kv/a").delete);
    try testing.expectEqualStrings("GET, PUT, DELETE", route("PATCH", "/kv/a").method_not_allowed);
    try testing.expectEqual(Route.bad_key, route("GET", "/kv/"));
    try testing.expectEqual(Route.bad_key, route("POST", "/kv/a/b"));
    try testing.expectEqual(Route.bad_key, route("GET", "/kv/bad.key"));
    try testing.expectEqual(Route.bad_key, route("GET", "/kv/" ++ "x" ** 65));
    try testing.expectEqualStrings("x" ** 64, route("GET", "/kv/" ++ "x" ** 64).get);
    try testing.expectEqual(Route.not_found, route("GET", "/nope"));
    try testing.expectEqual(Route.not_found, route("GET", "/health/"));
    try testing.expectEqual(Route.not_found, route("GET", "/kvx"));
}
