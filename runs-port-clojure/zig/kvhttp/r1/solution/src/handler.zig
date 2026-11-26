//! Routing and request handling for the kvhttp API, independent of the wire
//! protocol.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Status = std.http.Status;

const Store = @import("Store.zig");

pub const max_key_len = 64;

pub const Request = struct {
    method: []const u8,
    /// Request target without any query string.
    path: []const u8,
    body: []const u8 = "",
};

pub const Response = struct {
    status: Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    /// Value of the `Allow` header for 405 responses.
    allow: ?[]const u8 = null,

    fn methodNotAllowed(allow: []const u8) Response {
        return .{ .status = .method_not_allowed, .allow = allow };
    }
};

/// Handles one request. Response bodies are allocated with `arena`, which the
/// caller frees once the response has been sent.
pub fn handle(store: *Store, io: Io, arena: Allocator, req: Request) Allocator.Error!Response {
    if (std.mem.eql(u8, req.path, "/health")) {
        if (!isMethod(req, "GET")) return .methodNotAllowed("GET");
        return .{ .status = .ok, .body = "ok", .content_type = "text/plain; charset=utf-8" };
    }

    if (std.mem.eql(u8, req.path, "/kv")) {
        if (!isMethod(req, "GET")) return .methodNotAllowed("GET");
        const keys = try store.sortedKeys(io, arena);
        const json = try std.json.Stringify.valueAlloc(arena, keys, .{});
        return .{ .status = .ok, .body = json, .content_type = "application/json" };
    }

    if (std.mem.startsWith(u8, req.path, "/kv/")) {
        const key = req.path["/kv/".len..];
        if (!isValidKey(key)) return .{ .status = .bad_request };

        if (isMethod(req, "GET")) {
            const value = try store.get(io, arena, key) orelse return .{ .status = .not_found };
            return .{ .status = .ok, .body = value, .content_type = "application/octet-stream" };
        }
        if (isMethod(req, "PUT")) {
            const created = try store.put(io, key, req.body);
            return .{ .status = if (created) .created else .ok };
        }
        if (isMethod(req, "DELETE")) {
            return .{ .status = if (store.delete(io, key)) .no_content else .not_found };
        }
        return .methodNotAllowed("GET, PUT, DELETE");
    }

    return .{ .status = .not_found };
}

fn isMethod(req: Request, method: []const u8) bool {
    return std.mem.eql(u8, req.method, method);
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

const testing = std.testing;

const Harness = struct {
    arena: std.heap.ArenaAllocator,
    store: Store,

    fn init() Harness {
        return .{ .arena = .init(testing.allocator), .store = .init(testing.allocator) };
    }

    fn deinit(h: *Harness) void {
        h.store.deinit();
        h.arena.deinit();
    }

    fn do(h: *Harness, method: []const u8, path: []const u8, body: []const u8) !Response {
        return handle(&h.store, testing.io, h.arena.allocator(), .{ .method = method, .path = path, .body = body });
    }

    fn status(h: *Harness, method: []const u8, path: []const u8) !Status {
        return (try h.do(method, path, "")).status;
    }
};

test "crud" {
    var h: Harness = .init();
    defer h.deinit();

    try testing.expectEqual(.created, (try h.do("PUT", "/kv/a", "hello")).status);
    try testing.expectEqualStrings("hello", (try h.do("GET", "/kv/a", "")).body);
    try testing.expectEqual(.ok, (try h.do("PUT", "/kv/a", "world")).status);
    try testing.expectEqualStrings("world", (try h.do("GET", "/kv/a", "")).body);
    try testing.expectEqual(.no_content, try h.status("DELETE", "/kv/a"));
    try testing.expectEqual(.not_found, try h.status("GET", "/kv/a"));
    try testing.expectEqual(.not_found, try h.status("DELETE", "/kv/a"));
}

test "listing" {
    var h: Harness = .init();
    defer h.deinit();

    try testing.expectEqualStrings("[]", (try h.do("GET", "/kv", "")).body);
    for ([_][]const u8{ "/kv/b", "/kv/a", "/kv/c" }) |p| _ = try h.do("PUT", p, "x");
    const resp = try h.do("GET", "/kv", "");
    try testing.expectEqual(.ok, resp.status);
    try testing.expectEqualStrings("application/json", resp.content_type.?);
    try testing.expectEqualStrings("[\"a\",\"b\",\"c\"]", resp.body);
}

test "errors" {
    var h: Harness = .init();
    defer h.deinit();

    const long = "/kv/" ++ "a" ** 65;
    for ([_][]const u8{ "/kv/", "/kv/a/b", "/kv/bad.key", long }) |p|
        try testing.expectEqual(.bad_request, try h.status("GET", p));
    try testing.expectEqual(.bad_request, try h.status("PATCH", "/kv/bad.key"));
    for ([_][]const u8{ "/", "/nope", "/health/", "/kvx" }) |p|
        try testing.expectEqual(.not_found, try h.status("GET", p));
    try testing.expectEqual(.method_not_allowed, try h.status("POST", "/health"));
    try testing.expectEqual(.method_not_allowed, try h.status("PUT", "/kv"));
    try testing.expectEqual(.method_not_allowed, try h.status("PATCH", "/kv/a"));
    try testing.expectEqual(.method_not_allowed, try h.status("HEAD", "/kv/a"));
    try testing.expectEqual(.created, try h.status("PUT", "/kv/" ++ "a" ** 64));
}
