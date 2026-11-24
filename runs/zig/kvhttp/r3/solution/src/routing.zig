//! Maps request targets to routes.

const std = @import("std");

pub const max_key_len = 64;

/// A validated key, copied out of the request so it outlives the head buffer.
pub const Key = struct {
    buf: [max_key_len]u8,
    len: u8,

    pub fn slice(k: *const Key) []const u8 {
        return k.buf[0..k.len];
    }
};

pub const Route = union(enum) {
    health,
    list,
    item: Key,
    /// `/kv/<rest>` where `<rest>` is not a valid key.
    bad_key,
    not_found,
};

pub fn route(target: []const u8) Route {
    if (std.mem.eql(u8, target, "/health")) return .health;
    if (std.mem.eql(u8, target, "/kv")) return .list;
    const prefix = "/kv/";
    if (!std.mem.startsWith(u8, target, prefix)) return .not_found;
    const rest = target[prefix.len..];
    if (!isValidKey(rest)) return .bad_key;
    var key: Key = .{ .buf = undefined, .len = @intCast(rest.len) };
    @memcpy(key.buf[0..rest.len], rest);
    return .{ .item = key };
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

test route {
    try std.testing.expectEqual(Route.health, route("/health"));
    try std.testing.expectEqual(Route.list, route("/kv"));
    try std.testing.expectEqualStrings("a-B_9", route("/kv/a-B_9").item.slice());
    try std.testing.expectEqual(Route.bad_key, route("/kv/"));
    try std.testing.expectEqual(Route.bad_key, route("/kv/a/b"));
    try std.testing.expectEqual(Route.bad_key, route("/kv/bad.key"));
    try std.testing.expectEqual(Route.bad_key, route("/kv/" ++ "x" ** 65));
    try std.testing.expectEqualStrings("x" ** 64, route("/kv/" ++ "x" ** 64).item.slice());
    try std.testing.expectEqual(Route.not_found, route("/"));
    try std.testing.expectEqual(Route.not_found, route("/kvx"));
    try std.testing.expectEqual(Route.not_found, route("/health/"));
}
