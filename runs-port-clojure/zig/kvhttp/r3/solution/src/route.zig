//! Maps request targets onto the kvhttp resources.

const std = @import("std");

pub const max_key_len = 64;

pub const Route = union(enum) {
    /// `/health`
    health,
    /// `/kv`
    list,
    /// `/kv/<key>` with a valid key.
    entry: []const u8,
    /// `/kv/<rest>` where `<rest>` is not a valid key.
    invalid_key,
    /// Anything else.
    not_found,
};

const kv_prefix = "/kv/";

pub fn match(target: []const u8) Route {
    if (std.mem.eql(u8, target, "/health")) return .health;
    if (std.mem.eql(u8, target, "/kv")) return .list;
    if (std.mem.startsWith(u8, target, kv_prefix)) {
        const key = target[kv_prefix.len..];
        return if (isValidKey(key)) .{ .entry = key } else .invalid_key;
    }
    return .not_found;
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

test match {
    try testing.expectEqual(Route.health, match("/health"));
    try testing.expectEqual(Route.list, match("/kv"));
    try testing.expectEqualStrings("a-B_9", match("/kv/a-B_9").entry);
    try testing.expectEqual(Route.invalid_key, match("/kv/"));
    try testing.expectEqual(Route.invalid_key, match("/kv/a/b"));
    try testing.expectEqual(Route.invalid_key, match("/kv/bad.key"));
    try testing.expectEqual(Route.invalid_key, match("/kv/" ++ "x" ** 65));
    try testing.expectEqualStrings("x" ** 64, match("/kv/" ++ "x" ** 64).entry);
    try testing.expectEqual(Route.not_found, match("/"));
    try testing.expectEqual(Route.not_found, match("/kvx"));
    try testing.expectEqual(Route.not_found, match("/health/"));
}
