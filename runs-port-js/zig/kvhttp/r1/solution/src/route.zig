//! Maps request paths and methods to endpoints, independent of any I/O.

const std = @import("std");
const Method = std.http.Method;
const Status = std.http.Status;

pub const max_key_len = 64;

pub const Endpoint = union(enum) {
    health,
    list,
    item: []const u8,

    /// Value for the `Allow` header.
    pub fn allow(e: Endpoint) []const u8 {
        return switch (e) {
            .health, .list => "GET",
            .item => "GET, PUT, DELETE",
        };
    }

    /// `method` is null when the request used a method token that
    /// `std.http.Method` does not know; such methods are never allowed.
    pub fn allows(e: Endpoint, method: ?Method) bool {
        const m = method orelse return false;
        return switch (e) {
            .health, .list => m == .GET,
            .item => m == .GET or m == .PUT or m == .DELETE,
        };
    }
};

pub const Resolved = union(enum) {
    endpoint: Endpoint,
    /// The path cannot be served; respond with this status.
    failure: Status,
};

pub fn resolve(path: []const u8) Resolved {
    if (std.mem.eql(u8, path, "/health")) return .{ .endpoint = .health };
    if (std.mem.eql(u8, path, "/kv")) return .{ .endpoint = .list };
    if (std.mem.startsWith(u8, path, "/kv/")) {
        const key = path["/kv/".len..];
        if (!isValidKey(key)) return .{ .failure = .bad_request };
        return .{ .endpoint = .{ .item = key } };
    }
    return .{ .failure = .not_found };
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

test isValidKey {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("A-z_09"));
    try std.testing.expect(isValidKey("x" ** 64));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("x" ** 65));
    try std.testing.expect(!isValidKey("bad.key"));
    try std.testing.expect(!isValidKey("a/b"));
    try std.testing.expect(!isValidKey("a%20b"));
}

test resolve {
    try std.testing.expectEqual(Resolved{ .endpoint = .health }, resolve("/health"));
    try std.testing.expectEqual(Resolved{ .endpoint = .list }, resolve("/kv"));
    try std.testing.expectEqualStrings("abc", resolve("/kv/abc").endpoint.item);
    try std.testing.expectEqual(Resolved{ .failure = .bad_request }, resolve("/kv/"));
    try std.testing.expectEqual(Resolved{ .failure = .bad_request }, resolve("/kv/a/b"));
    try std.testing.expectEqual(Resolved{ .failure = .not_found }, resolve("/health/"));
    try std.testing.expectEqual(Resolved{ .failure = .not_found }, resolve("/kvx"));
    try std.testing.expectEqual(Resolved{ .failure = .not_found }, resolve("/"));
}
