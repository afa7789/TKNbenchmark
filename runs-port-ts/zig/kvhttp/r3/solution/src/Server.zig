//! The kvhttp HTTP server: accepts connections, routes requests and applies
//! them to the store. Each connection carries one request and is served by
//! its own concurrent task.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;

const http = @import("http.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.server);

const Server = @This();

io: Io,
gpa: Allocator,
store: *Store,

pub const max_value_len = 1024 * 1024;
pub const max_key_len = 64;

/// Request bodies nobody asked for (or that were rejected as too large) are
/// read and dropped up to this size so that closing the socket does not
/// reset the connection before the client has read the response.
const max_discard_len = 64 * 1024 * 1024;

/// Accepts connections forever, serving each one concurrently.
pub fn run(server: *Server, listener: *net.Server) Io.Cancelable!void {
    const io = server.io;
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                // Back off instead of spinning until connections are released.
                log.warn("accept failed: {t}", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        group.concurrent(io, serveConnection, .{ server, stream }) catch {
            // No more threads available: serve this connection inline.
            serveConnection(server, stream);
        };
    }
}

fn serveConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    var recv_buffer: [http.max_head_len]u8 = undefined;
    var send_buffer: [8 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);

    server.serveRequest(&stream_reader.interface, &stream_writer.interface) catch |err| switch (err) {
        error.ReadFailed => log.debug("read failed: {t}", .{stream_reader.err.?}),
        error.WriteFailed => log.debug("write failed: {t}", .{stream_writer.err.?}),
    };
}

const ServeError = error{ ReadFailed, WriteFailed };

fn serveRequest(server: *Server, in: *Io.Reader, out: *Io.Writer) ServeError!void {
    const head = http.readHead(in) catch |err| return switch (err) {
        // The client went away without sending a request.
        error.EndOfStream => {},
        error.ReadFailed => error.ReadFailed,
        error.HeadTooLarge => http.writeResponse(out, .plain(.request_header_fields_too_large)),
        error.BadRequest => http.writeResponse(out, .plain(.bad_request)),
        error.ExpectationFailed => http.writeResponse(out, .plain(.expectation_failed)),
    };

    // Holds response bodies until they have been written.
    var arena: std.heap.ArenaAllocator = .init(server.gpa);
    defer arena.deinit();

    var response = switch (resolve(head.method, head.target)) {
        .put => |key| try server.put(in, out, head, key),
        else => |route| blk: {
            discardBody(in, head) catch |err| switch (err) {
                error.ReadFailed => return error.ReadFailed,
                else => {},
            };
            break :blk server.apply(arena.allocator(), route);
        },
    };
    response.elide_body = std.mem.eql(u8, head.method, "HEAD");
    try http.writeResponse(out, response);
}

/// Handles `PUT /kv/<key>`: reads the value and stores it.
fn put(server: *Server, in: *Io.Reader, out: *Io.Writer, head: http.Head, key_ref: []const u8) ServeError!http.Response {
    // `key_ref` points into the read buffer, which reading the body reuses.
    var key_buffer: [max_key_len]u8 = undefined;
    const key = key_buffer[0..key_ref.len];
    @memcpy(key, key_ref);

    const declared_too_large = (head.content_length orelse 0) > max_value_len;
    if (head.expect_continue and !declared_too_large) try http.writeContinue(out);

    const value = http.readBody(in, server.gpa, head, max_value_len) catch |err| return switch (err) {
        error.ReadFailed => error.ReadFailed,
        error.EndOfStream => .plain(.bad_request),
        error.BadRequest => .plain(.bad_request),
        error.OutOfMemory => .plain(.internal_server_error),
        error.TooLarge => blk: {
            if (declared_too_large) discardBody(in, head) catch |e| switch (e) {
                error.ReadFailed => return error.ReadFailed,
                else => {},
            };
            break :blk .plain(.payload_too_large);
        },
    };

    const created = server.store.put(server.io, key, value) catch |err| {
        server.gpa.free(value);
        log.err("storing value failed: {t}", .{err});
        return .plain(.internal_server_error);
    };
    return .{ .status = if (created) .created else .ok };
}

/// Executes every route except `put`, which needs the request body.
/// Response bodies are allocated with `arena`.
fn apply(server: *Server, arena: Allocator, route: Route) http.Response {
    return server.applyFallible(arena, route) catch |err| {
        log.err("request failed: {t}", .{err});
        return .plain(.internal_server_error);
    };
}

fn applyFallible(server: *Server, arena: Allocator, route: Route) (Allocator.Error || Io.Cancelable)!http.Response {
    const io = server.io;
    return switch (route) {
        .health => .{ .status = .ok, .body = "ok" },
        .list => .{
            .status = .ok,
            .body = try server.store.keysJson(io, arena),
            .content_type = "application/json",
        },
        .get => |key| if (try server.store.get(io, arena, key)) |value| .{
            .status = .ok,
            .body = value,
            .content_type = "application/octet-stream",
        } else .plain(.not_found),
        .delete => |key| if (try server.store.remove(io, key)) .{ .status = .no_content } else .plain(.not_found),
        .reject => |response| response,
        .put => unreachable,
    };
}

/// Drops the request body unless the client is still waiting for
/// `100 Continue` before sending it.
fn discardBody(in: *Io.Reader, head: http.Head) http.BodyError!void {
    if (head.expect_continue or !head.hasBody()) return;
    try http.discardBody(in, head, max_discard_len);
}

pub const Route = union(enum) {
    health,
    list,
    get: []const u8,
    put: []const u8,
    delete: []const u8,
    /// The request is answered with this response without touching the store.
    reject: http.Response,
};

const kv_prefix = "/kv/";

/// Maps a request method and target to a route.
pub fn resolve(method: []const u8, target: []const u8) Route {
    if (std.mem.eql(u8, target, "/health")) {
        if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed("GET");
        return .health;
    }
    if (std.mem.eql(u8, target, "/kv")) {
        if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed("GET");
        return .list;
    }
    if (std.mem.startsWith(u8, target, kv_prefix)) {
        const key = target[kv_prefix.len..];
        if (!isValidKey(key)) return .{ .reject = .{ .status = .bad_request, .body = "invalid key" } };
        const Method = enum { GET, PUT, DELETE };
        return switch (std.meta.stringToEnum(Method, method) orelse return methodNotAllowed("GET, PUT, DELETE")) {
            .GET => .{ .get = key },
            .PUT => .{ .put = key },
            .DELETE => .{ .delete = key },
        };
    }
    return .{ .reject = .plain(.not_found) };
}

fn methodNotAllowed(allow: []const u8) Route {
    var response: http.Response = .plain(.method_not_allowed);
    response.allow = allow;
    return .{ .reject = response };
}

/// Reports whether `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

const testing = std.testing;

test isValidKey {
    try testing.expect(isValidKey("a"));
    try testing.expect(isValidKey("A-z_09"));
    try testing.expect(isValidKey("k" ** 64));
    try testing.expect(!isValidKey(""));
    try testing.expect(!isValidKey("k" ** 65));
    try testing.expect(!isValidKey("bad.key"));
    try testing.expect(!isValidKey("a/b"));
    try testing.expect(!isValidKey("%41"));
}

test resolve {
    try testing.expectEqual(Route.health, resolve("GET", "/health"));
    try testing.expectEqual(Route.list, resolve("GET", "/kv"));
    try testing.expectEqualStrings("abc", resolve("GET", "/kv/abc").get);
    try testing.expectEqualStrings("abc", resolve("PUT", "/kv/abc").put);
    try testing.expectEqualStrings("abc", resolve("DELETE", "/kv/abc").delete);

    try testing.expectEqual(.method_not_allowed, resolve("POST", "/health").reject.status);
    try testing.expectEqual(.method_not_allowed, resolve("HEAD", "/kv").reject.status);
    try testing.expectEqual(.method_not_allowed, resolve("PATCH", "/kv/a").reject.status);
    try testing.expectEqual(.bad_request, resolve("PATCH", "/kv/a.b").reject.status);
    try testing.expectEqual(.bad_request, resolve("GET", "/kv/").reject.status);
    try testing.expectEqual(.bad_request, resolve("GET", "/kv/a/b").reject.status);
    try testing.expectEqual(.not_found, resolve("GET", "/nope").reject.status);
    try testing.expectEqual(.not_found, resolve("GET", "/health/").reject.status);
    try testing.expectEqual(.not_found, resolve("GET", "/kvx").reject.status);
}
