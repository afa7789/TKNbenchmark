//! Maps requests to responses against the key-value store.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const http = @import("http.zig");
const Store = @import("Store.zig");
const Request = http.Request;
const Response = http.Response;

const kv_prefix = "/kv/";
const max_key_len = 64;

/// Handles `req`. Takes ownership of `req.body`. Any response body is
/// allocated with `gpa` and owned by the caller.
pub fn handle(store: *Store, io: Io, gpa: Allocator, req: Request) Allocator.Error!Response {
    const path = req.path;
    if (std.mem.eql(u8, path, "/health")) {
        gpa.free(req.body);
        if (!isMethod(req, "GET")) return .{ .status = .method_not_allowed, .allow = "GET" };
        return .{ .status = .ok, .body = try gpa.dupe(u8, "ok"), .content_type = "text/plain" };
    }
    if (std.mem.eql(u8, path, "/kv")) {
        gpa.free(req.body);
        if (!isMethod(req, "GET")) return .{ .status = .method_not_allowed, .allow = "GET" };
        return .{ .status = .ok, .body = try store.keysJson(io, gpa), .content_type = "application/json" };
    }
    if (std.mem.startsWith(u8, path, kv_prefix)) {
        const key = path[kv_prefix.len..];
        if (!isValidKey(key)) {
            gpa.free(req.body);
            return .{ .status = .bad_request };
        }
        return handleKey(store, io, gpa, req, key);
    }
    gpa.free(req.body);
    return .{ .status = .not_found };
}

fn handleKey(store: *Store, io: Io, gpa: Allocator, req: Request, key: []const u8) Allocator.Error!Response {
    if (isMethod(req, "PUT")) {
        const created = try store.put(io, key, req.body);
        return .{ .status = if (created) .created else .ok };
    }
    gpa.free(req.body);
    if (isMethod(req, "GET")) {
        const value = try store.getCopy(io, gpa, key) orelse return .{ .status = .not_found };
        return .{ .status = .ok, .body = value };
    }
    if (isMethod(req, "DELETE")) {
        return .{ .status = if (store.delete(io, key)) .no_content else .not_found };
    }
    return .{ .status = .method_not_allowed, .allow = "GET, PUT, DELETE" };
}

fn isMethod(req: Request, method: []const u8) bool {
    return std.mem.eql(u8, req.method, method);
}

pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

const testing = std.testing;

fn call(store: *Store, method: []const u8, path: []const u8, body: []const u8) !Response {
    return handle(store, testing.io, testing.allocator, .{
        .method = method,
        .path = path,
        .body = try testing.allocator.dupe(u8, body),
    });
}

fn expectStatus(store: *Store, status: http.Status, method: []const u8, path: []const u8, body: []const u8) !void {
    const res = try call(store, method, path, body);
    defer testing.allocator.free(res.body);
    try testing.expectEqual(status, res.status);
}

test "key validation" {
    try testing.expect(isValidKey("a"));
    try testing.expect(isValidKey("A-z_09"));
    try testing.expect(isValidKey("k" ** 64));
    try testing.expect(!isValidKey(""));
    try testing.expect(!isValidKey("k" ** 65));
    try testing.expect(!isValidKey("a/b"));
    try testing.expect(!isValidKey("bad.key"));
    try testing.expect(!isValidKey("caf\xc3\xa9"));
}

test "routes" {
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try expectStatus(&store, .ok, "GET", "/health", "");
    try expectStatus(&store, .method_not_allowed, "POST", "/health", "");
    try expectStatus(&store, .not_found, "GET", "/nope", "");
    try expectStatus(&store, .not_found, "GET", "/health/", "");
    try expectStatus(&store, .bad_request, "GET", "/kv/", "");
    try expectStatus(&store, .bad_request, "PATCH", "/kv/a.b", "");
    try expectStatus(&store, .method_not_allowed, "POST", "/kv", "");
    try expectStatus(&store, .created, "PUT", "/kv/a", "hello");
    try expectStatus(&store, .ok, "PUT", "/kv/a", "world");
    try expectStatus(&store, .method_not_allowed, "PATCH", "/kv/a", "");

    const got = try call(&store, "GET", "/kv/a", "");
    defer testing.allocator.free(got.body);
    try testing.expectEqualStrings("world", got.body);

    const list = try call(&store, "GET", "/kv", "");
    defer testing.allocator.free(list.body);
    try testing.expectEqualStrings("[\"a\"]", list.body);
    try testing.expectEqualStrings("application/json", list.content_type.?);

    try expectStatus(&store, .no_content, "DELETE", "/kv/a", "");
    try expectStatus(&store, .not_found, "DELETE", "/kv/a", "");
    try expectStatus(&store, .not_found, "GET", "/kv/a", "");
}
