//! Maps requests onto the key/value API.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const http = @import("http.zig");
const Store = @import("Store.zig");

const kv_prefix = "/kv/";
const max_key_len = 64;

/// True if `key` matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

/// Handles `req`. Response bodies are allocated with `arena`.
pub fn handle(io: Io, arena: Allocator, store: *Store, req: *const http.Request) Allocator.Error!http.Response {
    const path = req.target;
    const method = req.method;

    if (std.mem.eql(u8, path, "/health")) {
        if (!std.mem.eql(u8, method, "GET")) return .empty(.method_not_allowed);
        return .{ .content_type = "text/plain", .body = "ok" };
    }

    if (std.mem.eql(u8, path, "/kv")) {
        if (!std.mem.eql(u8, method, "GET")) return .empty(.method_not_allowed);
        return .{
            .content_type = "application/json",
            .body = try jsonStringArray(arena, try store.keys(io, arena)),
        };
    }

    if (std.mem.startsWith(u8, path, kv_prefix)) {
        const key = path[kv_prefix.len..];
        if (!isValidKey(key)) return .empty(.bad_request);
        return handleKey(io, arena, store, method, key, req.body);
    }

    return .empty(.not_found);
}

fn handleKey(
    io: Io,
    arena: Allocator,
    store: *Store,
    method: []const u8,
    key: []const u8,
    body: []const u8,
) Allocator.Error!http.Response {
    if (std.mem.eql(u8, method, "GET")) {
        const value = try store.get(io, arena, key) orelse return .empty(.not_found);
        return .{ .content_type = "application/octet-stream", .body = value };
    }
    if (std.mem.eql(u8, method, "PUT")) {
        return switch (try store.put(io, key, body)) {
            .created => .empty(.created),
            .replaced => .empty(.ok),
        };
    }
    if (std.mem.eql(u8, method, "DELETE")) {
        return .empty(if (store.remove(io, key)) .no_content else .not_found);
    }
    return .empty(.method_not_allowed);
}

/// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is ever required.
fn jsonStringArray(arena: Allocator, items: []const []const u8) Allocator.Error![]const u8 {
    var size: usize = 2;
    for (items) |item| size += item.len + 3;
    var out: std.ArrayList(u8) = try .initCapacity(arena, size);
    out.appendAssumeCapacity('[');
    for (items, 0..) |item, i| {
        if (i != 0) out.appendAssumeCapacity(',');
        out.appendAssumeCapacity('"');
        out.appendSliceAssumeCapacity(item);
        out.appendAssumeCapacity('"');
    }
    out.appendAssumeCapacity(']');
    return out.items;
}

test isValidKey {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("A-z_09"));
    try std.testing.expect(isValidKey("k" ** 64));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("k" ** 65));
    try std.testing.expect(!isValidKey("a/b"));
    try std.testing.expect(!isValidKey("bad.key"));
    try std.testing.expect(!isValidKey("a%20"));
}

test "routes and status codes" {
    const io = std.testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    const Case = struct { method: []const u8, target: []const u8, body: []const u8 = "", status: http.Status };
    const cases = [_]Case{
        .{ .method = "GET", .target = "/health", .status = .ok },
        .{ .method = "POST", .target = "/health", .status = .method_not_allowed },
        .{ .method = "PUT", .target = "/kv/b", .body = "2", .status = .created },
        .{ .method = "PUT", .target = "/kv/a", .body = "1", .status = .created },
        .{ .method = "PUT", .target = "/kv/a", .body = "one", .status = .ok },
        .{ .method = "GET", .target = "/kv/a", .status = .ok },
        .{ .method = "PATCH", .target = "/kv/a", .status = .method_not_allowed },
        .{ .method = "GET", .target = "/kv/", .status = .bad_request },
        .{ .method = "GET", .target = "/kv/a/b", .status = .bad_request },
        .{ .method = "POST", .target = "/kv", .status = .method_not_allowed },
        .{ .method = "GET", .target = "/nope", .status = .not_found },
        .{ .method = "DELETE", .target = "/kv/b", .status = .no_content },
        .{ .method = "DELETE", .target = "/kv/b", .status = .not_found },
        .{ .method = "GET", .target = "/kv/b", .status = .not_found },
    };
    for (cases) |c| {
        const req: http.Request = .{ .method = c.method, .target = c.target, .headers = &.{}, .body = c.body };
        const res = try handle(io, arena, &store, &req);
        try std.testing.expectEqual(c.status, res.status);
    }

    const req: http.Request = .{ .method = "GET", .target = "/kv", .headers = &.{}, .body = "" };
    const res = try handle(io, arena, &store, &req);
    try std.testing.expectEqualStrings("[\"a\"]", res.body);
    try std.testing.expectEqualStrings("application/json", res.content_type.?);
}
