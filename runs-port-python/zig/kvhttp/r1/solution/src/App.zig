//! Request routing for the key-value API.

const App = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const mem = std.mem;

const Store = @import("Store.zig");
const http = @import("http.zig");
const Request = http.Request;
const Response = http.Response;

store: *Store,

const kv_prefix = "/kv/";
const max_key_len = 64;

pub const Error = Allocator.Error || Io.Cancelable;

/// Dispatches `req`. Response bodies are allocated with `arena`.
pub fn handle(app: App, io: Io, arena: Allocator, req: Request) Error!Response {
    const path = req.path;
    if (mem.eql(u8, path, "/health")) {
        if (!mem.eql(u8, req.method, "GET")) return methodNotAllowed("GET");
        return .{ .status = .ok, .body = "ok", .content_type = "text/plain" };
    }
    if (mem.eql(u8, path, "/kv")) {
        if (!mem.eql(u8, req.method, "GET")) return methodNotAllowed("GET");
        const keys = try app.store.keys(io, arena);
        const body = try std.json.Stringify.valueAlloc(arena, keys, .{});
        return .{ .status = .ok, .body = body, .content_type = "application/json" };
    }
    if (mem.startsWith(u8, path, kv_prefix)) {
        const key = path[kv_prefix.len..];
        if (!isValidKey(key)) return .{ .status = .bad_request };
        return app.handleKey(io, arena, req, key);
    }
    return .{ .status = .not_found };
}

fn handleKey(app: App, io: Io, arena: Allocator, req: Request, key: []const u8) Error!Response {
    const Method = enum { GET, PUT, DELETE };
    const method = std.meta.stringToEnum(Method, req.method) orelse
        return methodNotAllowed("GET, PUT, DELETE");
    switch (method) {
        .GET => {
            const value = try app.store.get(io, arena, key) orelse return .{ .status = .not_found };
            return .{ .status = .ok, .body = value, .content_type = "application/octet-stream" };
        },
        .PUT => return switch (try app.store.put(io, key, req.body)) {
            .created => .{ .status = .created },
            .replaced => .{ .status = .ok },
        },
        .DELETE => return .{ .status = if (try app.store.delete(io, key)) .no_content else .not_found },
    }
}

fn methodNotAllowed(allow: []const u8) Response {
    return .{ .status = .method_not_allowed, .allow = allow };
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

test isValidKey {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("A-z_09"));
    try std.testing.expect(isValidKey("x" ** 64));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("x" ** 65));
    try std.testing.expect(!isValidKey("a/b"));
    try std.testing.expect(!isValidKey("bad.key"));
    try std.testing.expect(!isValidKey("caf\xc3\xa9"));
}

test "routing" {
    const io = std.testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var store: Store = .init(std.testing.allocator);
    defer store.deinit();
    const app: App = .{ .store = &store };

    const Case = struct { method: []const u8, path: []const u8, body: []const u8 = "", status: http.Status, out: ?[]const u8 = null };
    const cases = [_]Case{
        .{ .method = "GET", .path = "/health", .status = .ok, .out = "ok" },
        .{ .method = "POST", .path = "/health", .status = .method_not_allowed },
        .{ .method = "GET", .path = "/nope", .status = .not_found },
        .{ .method = "GET", .path = "/kv/", .status = .bad_request },
        .{ .method = "GET", .path = "/kv/a/b", .status = .bad_request },
        .{ .method = "PUT", .path = "/kv/b", .body = "2", .status = .created },
        .{ .method = "PUT", .path = "/kv/a", .body = "1", .status = .created },
        .{ .method = "PUT", .path = "/kv/a", .body = "one", .status = .ok },
        .{ .method = "GET", .path = "/kv/a", .status = .ok, .out = "one" },
        .{ .method = "PATCH", .path = "/kv/a", .status = .method_not_allowed },
        .{ .method = "GET", .path = "/kv", .status = .ok, .out = "[\"a\",\"b\"]" },
        .{ .method = "DELETE", .path = "/kv", .status = .method_not_allowed },
        .{ .method = "DELETE", .path = "/kv/a", .status = .no_content },
        .{ .method = "DELETE", .path = "/kv/a", .status = .not_found },
        .{ .method = "GET", .path = "/kv/a", .status = .not_found },
    };
    for (cases) |c| {
        const res = try app.handle(io, arena, .{ .method = c.method, .path = c.path, .body = c.body });
        try std.testing.expectEqual(c.status, res.status);
        if (c.out) |out| try std.testing.expectEqualStrings(out, res.body);
    }
}
