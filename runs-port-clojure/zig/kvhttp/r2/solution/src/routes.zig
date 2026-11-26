//! Pure request-target routing, independent of any I/O.

const std = @import("std");

pub const max_key_len = 64;

pub const Route = union(enum) {
    /// `/health`
    health,
    /// `/kv`
    list,
    /// `/kv/<key>` with a valid key.
    item: []const u8,
    /// `/kv/<rest>` where `<rest>` is not a valid key.
    invalid_key,
    /// Anything else.
    not_found,
};

pub fn match(target: []const u8) Route {
    if (std.mem.eql(u8, target, "/health")) return .health;
    if (std.mem.eql(u8, target, "/kv")) return .list;
    if (std.mem.startsWith(u8, target, "/kv/")) {
        const key = target["/kv/".len..];
        return if (isValidKey(key)) .{ .item = key } else .invalid_key;
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

test match {
    const t = std.testing;
    try t.expectEqual(Route.health, match("/health"));
    try t.expectEqual(Route.list, match("/kv"));
    try t.expectEqualStrings("a-B_9", match("/kv/a-B_9").item);
    try t.expectEqual(Route.invalid_key, match("/kv/"));
    try t.expectEqual(Route.invalid_key, match("/kv/a/b"));
    try t.expectEqual(Route.invalid_key, match("/kv/bad.key"));
    try t.expectEqual(Route.invalid_key, match("/kv/a%20b"));
    try t.expectEqual(Route.not_found, match("/"));
    try t.expectEqual(Route.not_found, match("/kvx"));
    try t.expectEqual(Route.not_found, match("/health/"));
}

test isValidKey {
    const t = std.testing;
    try t.expect(isValidKey("a" ** 64));
    try t.expect(!isValidKey("a" ** 65));
    try t.expect(!isValidKey(""));
    try t.expect(!isValidKey("é"));
}
