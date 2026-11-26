//! Maps a request method and path to the action the server must perform.

const std = @import("std");

pub const max_key_len = 64;
const kv_prefix = "/kv/";

pub const Route = union(enum) {
    health,
    list_keys,
    get: []const u8,
    put: []const u8,
    delete: []const u8,
    /// The request is answered with a bare status code and no body.
    status: std.http.Status,
};

/// `path` is the raw request target; `key` slices in the result point into it.
pub fn resolve(method: []const u8, path: []const u8) Route {
    if (std.mem.eql(u8, path, "/health")) {
        return if (isMethod(method, "GET")) .health else .{ .status = .method_not_allowed };
    }
    if (std.mem.eql(u8, path, "/kv")) {
        return if (isMethod(method, "GET")) .list_keys else .{ .status = .method_not_allowed };
    }
    if (std.mem.startsWith(u8, path, kv_prefix)) {
        const key = path[kv_prefix.len..];
        if (!isValidKey(key)) return .{ .status = .bad_request };
        if (isMethod(method, "GET")) return .{ .get = key };
        if (isMethod(method, "PUT")) return .{ .put = key };
        if (isMethod(method, "DELETE")) return .{ .delete = key };
        return .{ .status = .method_not_allowed };
    }
    return .{ .status = .not_found };
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

/// HTTP methods are case-sensitive.
fn isMethod(method: []const u8, comptime expected: []const u8) bool {
    return std.mem.eql(u8, method, expected);
}

const testing = std.testing;

fn expectRoute(expected: Route, method: []const u8, path: []const u8) !void {
    try testing.expectEqualDeep(expected, resolve(method, path));
}

test "routes" {
    try expectRoute(.health, "GET", "/health");
    try expectRoute(.list_keys, "GET", "/kv");
    try expectRoute(.{ .get = "a" }, "GET", "/kv/a");
    try expectRoute(.{ .put = "A-z_09" }, "PUT", "/kv/A-z_09");
    try expectRoute(.{ .delete = "a" }, "DELETE", "/kv/a");
}

test "method not allowed" {
    try expectRoute(.{ .status = .method_not_allowed }, "POST", "/health");
    try expectRoute(.{ .status = .method_not_allowed }, "HEAD", "/health");
    try expectRoute(.{ .status = .method_not_allowed }, "PUT", "/kv");
    try expectRoute(.{ .status = .method_not_allowed }, "PATCH", "/kv/a");
    try expectRoute(.{ .status = .method_not_allowed }, "get", "/kv/a");
    try expectRoute(.{ .status = .method_not_allowed }, "FROB", "/kv/a");
}

test "invalid keys" {
    try expectRoute(.{ .status = .bad_request }, "GET", "/kv/");
    try expectRoute(.{ .status = .bad_request }, "GET", "/kv/bad.key");
    try expectRoute(.{ .status = .bad_request }, "PUT", "/kv/a/b");
    try expectRoute(.{ .status = .bad_request }, "GET", "/kv/a%20b");
    try expectRoute(.{ .status = .bad_request }, "PATCH", "/kv/bad.key");
    try expectRoute(.{ .status = .bad_request }, "GET", "/kv/" ++ "k" ** 65);
    try expectRoute(.{ .get = "k" ** 64 }, "GET", "/kv/" ++ "k" ** 64);
}

test "unknown paths" {
    try expectRoute(.{ .status = .not_found }, "GET", "/");
    try expectRoute(.{ .status = .not_found }, "GET", "/nope");
    try expectRoute(.{ .status = .not_found }, "GET", "/health/");
    try expectRoute(.{ .status = .not_found }, "GET", "/kvx");
    try expectRoute(.{ .status = .not_found }, "POST", "/kvs/a");
}
