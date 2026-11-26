//! Dispatches requests against the key-value API.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const http = @import("http.zig");
const KvStore = @import("KvStore.zig");
const Response = http.Response;
const Request = http.Request;

const kv_prefix = "/kv/";
const max_key_len = 64;

pub const Error = Allocator.Error || Io.Cancelable;

/// Returns true if `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

/// Produces the response for `request`. Response data is allocated with `arena`.
pub fn route(store: *KvStore, io: Io, arena: Allocator, request: Request) Error!Response {
    const path = request.target;
    if (std.mem.eql(u8, path, "/health")) return handleHealth(request);
    if (std.mem.eql(u8, path, "/kv")) return handleList(store, io, arena, request);
    if (std.mem.startsWith(u8, path, kv_prefix)) {
        return handleKey(store, io, arena, request, path[kv_prefix.len..]);
    }
    return .text(404, "not found");
}

fn methodNotAllowed(comptime allow: []const u8) Response {
    return .{
        .status = 405,
        .headers = &.{
            .{ .name = "Content-Type", .value = "text/plain; charset=utf-8" },
            .{ .name = "Allow", .value = allow },
        },
        .body = "Method Not Allowed",
    };
}

fn isMethod(request: Request, method: []const u8) bool {
    return std.mem.eql(u8, request.method, method);
}

fn handleHealth(request: Request) Response {
    if (!isMethod(request, "GET")) return methodNotAllowed("GET");
    return .text(200, "ok");
}

fn handleList(store: *KvStore, io: Io, arena: Allocator, request: Request) Error!Response {
    if (!isMethod(request, "GET")) return methodNotAllowed("GET");

    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is required.
    const keys = try store.keys(io, arena);
    var body: std.Io.Writer.Allocating = .init(arena);
    const w = &body.writer;
    w.writeByte('[') catch return error.OutOfMemory;
    for (keys, 0..) |key, i| {
        if (i != 0) w.writeByte(',') catch return error.OutOfMemory;
        w.print("\"{s}\"", .{key}) catch return error.OutOfMemory;
    }
    w.writeByte(']') catch return error.OutOfMemory;

    return .{
        .status = 200,
        .headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
        .body = body.written(),
    };
}

fn handleKey(store: *KvStore, io: Io, arena: Allocator, request: Request, key: []const u8) Error!Response {
    if (!isValidKey(key)) return .text(400, "invalid key");

    if (isMethod(request, "GET")) {
        const value = try store.get(io, arena, key) orelse return .text(404, "not found");
        return .{
            .status = 200,
            .headers = &.{.{ .name = "Content-Type", .value = "application/octet-stream" }},
            .body = value,
        };
    }
    if (isMethod(request, "PUT")) {
        return switch (try store.put(io, key, request.body)) {
            .created => .empty(201),
            .replaced => .empty(200),
        };
    }
    if (isMethod(request, "DELETE")) {
        return if (try store.remove(io, key)) .empty(204) else .text(404, "not found");
    }
    return methodNotAllowed("GET, PUT, DELETE");
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
}

test route {
    const io = testing.io;
    var store: KvStore = .init(testing.allocator);
    defer store.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const Case = struct { method: []const u8, target: []const u8, body: []const u8 = "", status: u16, response: ?[]const u8 = null };
    const cases = [_]Case{
        .{ .method = "GET", .target = "/health", .status = 200, .response = "ok" },
        .{ .method = "POST", .target = "/health", .status = 405 },
        .{ .method = "GET", .target = "/nope", .status = 404 },
        .{ .method = "GET", .target = "/kv/", .status = 400 },
        .{ .method = "PATCH", .target = "/kv/a.b", .status = 400 },
        .{ .method = "PUT", .target = "/kv/b", .body = "2", .status = 201 },
        .{ .method = "PUT", .target = "/kv/a", .body = "1", .status = 201 },
        .{ .method = "PUT", .target = "/kv/a", .body = "x", .status = 200 },
        .{ .method = "GET", .target = "/kv/a", .status = 200, .response = "x" },
        .{ .method = "PATCH", .target = "/kv/a", .status = 405 },
        .{ .method = "GET", .target = "/kv", .status = 200, .response = "[\"a\",\"b\"]" },
        .{ .method = "DELETE", .target = "/kv", .status = 405 },
        .{ .method = "DELETE", .target = "/kv/a", .status = 204 },
        .{ .method = "DELETE", .target = "/kv/a", .status = 404 },
        .{ .method = "GET", .target = "/kv/a", .status = 404 },
    };
    for (cases) |c| {
        const response = try route(&store, io, arena, .{ .method = c.method, .target = c.target, .headers = &.{}, .body = c.body });
        try testing.expectEqual(c.status, response.status);
        if (c.response) |body| try testing.expectEqualStrings(body, response.body);
    }
}
