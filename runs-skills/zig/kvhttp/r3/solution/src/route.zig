//! Maps a request method and path onto an application action.
const std = @import("std");

pub const max_key_len = 64;

pub const Method = enum { GET, PUT, DELETE, other };

pub const Route = union(enum) {
    health,
    list,
    get: []const u8,
    put: []const u8,
    delete: []const u8,
    bad_key,
    not_found,
    method_not_allowed,
};

pub fn resolve(method: Method, path: []const u8) Route {
    if (std.mem.eql(u8, path, "/health")) {
        return if (method == .GET) .health else .method_not_allowed;
    }
    if (std.mem.eql(u8, path, "/kv")) {
        return if (method == .GET) .list else .method_not_allowed;
    }
    const prefix = "/kv/";
    if (std.mem.startsWith(u8, path, prefix)) {
        const key = path[prefix.len..];
        if (!isValidKey(key)) return .bad_key;
        return switch (method) {
            .GET => .{ .get = key },
            .PUT => .{ .put = key },
            .DELETE => .{ .delete = key },
            .other => .method_not_allowed,
        };
    }
    return .not_found;
}

pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

test resolve {
    const t = std.testing;
    try t.expectEqual(Route.health, resolve(.GET, "/health"));
    try t.expectEqual(Route.method_not_allowed, resolve(.other, "/health"));
    try t.expectEqual(Route.list, resolve(.GET, "/kv"));
    try t.expectEqual(Route.method_not_allowed, resolve(.PUT, "/kv"));
    try t.expectEqualStrings("a-B_9", resolve(.PUT, "/kv/a-B_9").put);
    try t.expectEqual(Route.method_not_allowed, resolve(.other, "/kv/a"));
    try t.expectEqual(Route.bad_key, resolve(.GET, "/kv/"));
    try t.expectEqual(Route.bad_key, resolve(.GET, "/kv/a/b"));
    try t.expectEqual(Route.bad_key, resolve(.GET, "/kv/bad.key"));
    try t.expectEqual(Route.bad_key, resolve(.GET, "/kv/" ++ "x" ** 65));
    try t.expectEqual(Route.not_found, resolve(.GET, "/nope"));
    try t.expectEqual(Route.not_found, resolve(.GET, "/health/"));
}
