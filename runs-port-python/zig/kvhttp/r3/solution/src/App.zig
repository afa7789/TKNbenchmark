//! Request routing for the key-value API.

const App = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const http = @import("http.zig");
const Store = @import("Store.zig");

store: *Store,

pub const max_key_len = 64;

pub const Error = Allocator.Error || Io.Cancelable;

/// Produces the response for `req`. Response memory is allocated with `arena`.
pub fn handle(app: App, io: Io, arena: Allocator, req: http.Request) Error!http.Response {
    if (std.mem.eql(u8, req.path, "/health")) {
        if (!isMethod(req, "GET")) return methodNotAllowed("GET");
        return .{ .status = .ok, .body = "ok", .content_type = "text/plain; charset=utf-8" };
    }
    if (std.mem.eql(u8, req.path, "/kv")) {
        if (!isMethod(req, "GET")) return methodNotAllowed("GET");
        return .{ .status = .ok, .body = try app.listKeys(io, arena), .content_type = "application/json" };
    }
    if (std.mem.startsWith(u8, req.path, "/kv/")) {
        const key = req.path["/kv/".len..];
        if (!isValidKey(key)) return .{ .status = .bad_request };
        return app.handleKey(io, arena, req, key);
    }
    return .{ .status = .not_found };
}

fn handleKey(app: App, io: Io, arena: Allocator, req: http.Request, key: []const u8) Error!http.Response {
    if (isMethod(req, "GET")) {
        const value = try app.store.get(io, arena, key) orelse return .{ .status = .not_found };
        return .{ .status = .ok, .body = value, .content_type = "application/octet-stream" };
    }
    if (isMethod(req, "PUT")) {
        return switch (try app.store.put(io, key, req.body)) {
            .created => .{ .status = .created },
            .replaced => .{ .status = .ok },
        };
    }
    if (isMethod(req, "DELETE")) {
        const deleted = try app.store.delete(io, key);
        return .{ .status = if (deleted) .no_content else .not_found };
    }
    return methodNotAllowed("GET, PUT, DELETE");
}

fn listKeys(app: App, io: Io, arena: Allocator) Error![]const u8 {
    const keys = try app.store.sortedKeys(io, arena);
    var out: Io.Writer.Allocating = .init(arena);
    std.json.Stringify.value(keys, .{}, &out.writer) catch return error.OutOfMemory;
    return out.written();
}

fn isMethod(req: http.Request, method: []const u8) bool {
    return std.mem.eql(u8, req.method, method);
}

fn methodNotAllowed(allow: []const u8) http.Response {
    return .{ .status = .method_not_allowed, .allow = allow };
}

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

const testing = std.testing;

test isValidKey {
    try testing.expect(isValidKey("a"));
    try testing.expect(isValidKey("A-z_09"));
    try testing.expect(isValidKey("k" ** 64));
    try testing.expect(!isValidKey(""));
    try testing.expect(!isValidKey("k" ** 65));
    try testing.expect(!isValidKey("a/b"));
    try testing.expect(!isValidKey("bad.key"));
    try testing.expect(!isValidKey("caf\xc3\xa9"));
}

test "routing" {
    const io = testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var store: Store = .init(testing.allocator);
    defer store.deinit();
    const app: App = .{ .store = &store };

    const Case = struct { method: []const u8, path: []const u8, body: []const u8 = "", status: http.Status, response: ?[]const u8 = null };
    const cases = [_]Case{
        .{ .method = "GET", .path = "/health", .status = .ok, .response = "ok" },
        .{ .method = "POST", .path = "/health", .status = .method_not_allowed },
        .{ .method = "GET", .path = "/kv", .status = .ok, .response = "[]" },
        .{ .method = "PUT", .path = "/kv/b", .body = "2", .status = .created },
        .{ .method = "PUT", .path = "/kv/a", .body = "1", .status = .created },
        .{ .method = "PUT", .path = "/kv/a", .body = "one", .status = .ok },
        .{ .method = "GET", .path = "/kv/a", .status = .ok, .response = "one" },
        .{ .method = "GET", .path = "/kv", .status = .ok, .response = "[\"a\",\"b\"]" },
        .{ .method = "DELETE", .path = "/kv", .status = .method_not_allowed },
        .{ .method = "PATCH", .path = "/kv/a", .status = .method_not_allowed },
        .{ .method = "PATCH", .path = "/kv/a.b", .status = .bad_request },
        .{ .method = "GET", .path = "/kv/", .status = .bad_request },
        .{ .method = "GET", .path = "/kv/a/b", .status = .bad_request },
        .{ .method = "DELETE", .path = "/kv/a", .status = .no_content },
        .{ .method = "DELETE", .path = "/kv/a", .status = .not_found },
        .{ .method = "GET", .path = "/kv/a", .status = .not_found },
        .{ .method = "GET", .path = "/nope", .status = .not_found },
        .{ .method = "GET", .path = "/health/", .status = .not_found },
    };
    for (cases) |c| {
        const resp = try app.handle(io, arena, .{ .method = c.method, .path = c.path, .body = c.body });
        try testing.expectEqual(c.status, resp.status);
        if (c.response) |expected| try testing.expectEqualStrings(expected, resp.body);
    }
}
