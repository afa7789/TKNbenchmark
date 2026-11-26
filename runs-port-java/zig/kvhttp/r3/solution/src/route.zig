//! Maps a request method and path to an action, independent of any I/O.

const std = @import("std");
const http = std.http;

pub const max_key_len = 64;

pub const Action = union(enum) {
    health,
    list_keys,
    get_value: []const u8,
    put_value: []const u8,
    delete_value: []const u8,
    /// Respond with this status and an empty body.
    status: http.Status,
};

/// `method` is `null` for request methods unknown to `std.http.Method`;
/// such requests are treated like any other unsupported method.
/// Returned key slices point into `target`.
pub fn resolve(method: ?http.Method, target: []const u8) Action {
    // Request paths are not expected to carry a query string, but ignore one
    // if present so it cannot leak into the key.
    const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];

    if (std.mem.eql(u8, path, "/health")) {
        return if (method == .GET) .health else .{ .status = .method_not_allowed };
    }
    if (std.mem.eql(u8, path, "/kv")) {
        return if (method == .GET) .list_keys else .{ .status = .method_not_allowed };
    }
    const prefix = "/kv/";
    if (std.mem.startsWith(u8, path, prefix)) {
        const key = path[prefix.len..];
        if (!isValidKey(key)) return .{ .status = .bad_request };
        return switch (method orelse return .{ .status = .method_not_allowed }) {
            .GET => .{ .get_value = key },
            .PUT => .{ .put_value = key },
            .DELETE => .{ .delete_value = key },
            else => .{ .status = .method_not_allowed },
        };
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
    try testing.expect(!isValidKey("caf\xc3\xa9"));
}

test resolve {
    try testing.expectEqual(Action.health, resolve(.GET, "/health"));
    try testing.expectEqual(Action{ .status = .method_not_allowed }, resolve(.POST, "/health"));
    try testing.expectEqual(Action{ .status = .method_not_allowed }, resolve(null, "/health"));
    try testing.expectEqual(Action.list_keys, resolve(.GET, "/kv"));
    try testing.expectEqual(Action{ .status = .method_not_allowed }, resolve(.DELETE, "/kv"));
    try testing.expectEqualStrings("a", resolve(.GET, "/kv/a").get_value);
    try testing.expectEqualStrings("a", resolve(.PUT, "/kv/a").put_value);
    try testing.expectEqualStrings("a", resolve(.DELETE, "/kv/a").delete_value);
    try testing.expectEqual(Action{ .status = .method_not_allowed }, resolve(.PATCH, "/kv/a"));
    try testing.expectEqual(Action{ .status = .method_not_allowed }, resolve(null, "/kv/a"));
    try testing.expectEqual(Action{ .status = .bad_request }, resolve(.GET, "/kv/"));
    try testing.expectEqual(Action{ .status = .bad_request }, resolve(.PATCH, "/kv/a/b"));
    try testing.expectEqual(Action{ .status = .bad_request }, resolve(.GET, "/kv/bad.key"));
    try testing.expectEqual(Action{ .status = .not_found }, resolve(.GET, "/nope"));
    try testing.expectEqual(Action{ .status = .not_found }, resolve(.GET, "/"));
    try testing.expectEqual(Action{ .status = .not_found }, resolve(.GET, "/kvx"));
    try testing.expectEqual(Action{ .status = .not_found }, resolve(.GET, "/health/"));
}
