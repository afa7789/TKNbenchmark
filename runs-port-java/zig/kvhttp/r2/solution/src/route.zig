//! Maps a request line (method and path) onto an API operation.

const std = @import("std");
const Status = std.http.Status;

pub const max_key_len = 64;

pub const Route = union(enum) {
    health,
    list_keys,
    get: []const u8,
    put: []const u8,
    delete: []const u8,
    /// The request cannot be served; respond with this status and no body.
    reject: Status,
};

/// `target` is the raw request target. Returned key slices point into it.
pub fn resolve(method: []const u8, target: []const u8) Route {
    const eql = std.mem.eql;

    if (eql(u8, target, "/health")) {
        return if (eql(u8, method, "GET")) .health else .{ .reject = .method_not_allowed };
    }
    if (eql(u8, target, "/kv")) {
        return if (eql(u8, method, "GET")) .list_keys else .{ .reject = .method_not_allowed };
    }
    const prefix = "/kv/";
    if (std.mem.startsWith(u8, target, prefix)) {
        const key = target[prefix.len..];
        if (!isValidKey(key)) return .{ .reject = .bad_request };
        if (eql(u8, method, "GET")) return .{ .get = key };
        if (eql(u8, method, "PUT")) return .{ .put = key };
        if (eql(u8, method, "DELETE")) return .{ .delete = key };
        return .{ .reject = .method_not_allowed };
    }
    return .{ .reject = .not_found };
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
    try testing.expectEqual(Route{ .reject = .method_not_allowed }, resolve("POST", "/health"));
    try testing.expectEqual(Route{ .reject = .method_not_allowed }, resolve("HEAD", "/health"));
    try testing.expectEqual(Route.list_keys, resolve("GET", "/kv"));
    try testing.expectEqual(Route{ .reject = .method_not_allowed }, resolve("DELETE", "/kv"));
    try testing.expectEqualStrings("abc", resolve("PUT", "/kv/abc").put);
    try testing.expectEqualStrings("abc", resolve("GET", "/kv/abc").get);
    try testing.expectEqualStrings("abc", resolve("DELETE", "/kv/abc").delete);
    try testing.expectEqual(Route{ .reject = .method_not_allowed }, resolve("PATCH", "/kv/a"));
    try testing.expectEqual(Route{ .reject = .bad_request }, resolve("GET", "/kv/"));
    try testing.expectEqual(Route{ .reject = .bad_request }, resolve("PATCH", "/kv/a/b"));
    try testing.expectEqual(Route{ .reject = .not_found }, resolve("GET", "/nope"));
    try testing.expectEqual(Route{ .reject = .not_found }, resolve("GET", "/kvx"));
    try testing.expectEqual(Route{ .reject = .not_found }, resolve("GET", "/health/"));
}
