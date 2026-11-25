//! Maps a request method and target to an action. Pure; no I/O.

const std = @import("std");
const http = std.http;

pub const max_key_len = 64;

/// A validated key, copied out of the request head (whose memory is
/// invalidated once the body is read).
pub const Key = struct {
    buf: [max_key_len]u8,
    len: u8,

    pub fn init(s: []const u8) ?Key {
        if (s.len == 0 or s.len > max_key_len) return null;
        for (s) |c| switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
            else => return null,
        };
        var key: Key = .{ .buf = undefined, .len = @intCast(s.len) };
        @memcpy(key.buf[0..s.len], s);
        return key;
    }

    pub fn slice(k: *const Key) []const u8 {
        return k.buf[0..k.len];
    }
};

pub const Action = union(enum) {
    health,
    list,
    get: Key,
    put: Key,
    delete: Key,
    err: http.Status,
};

/// `method` is null for methods outside `std.http.Method`.
pub fn resolve(method: ?http.Method, target: []const u8) Action {
    if (std.mem.eql(u8, target, "/health")) {
        return if (method == .GET) .health else .{ .err = .method_not_allowed };
    }
    if (std.mem.eql(u8, target, "/kv")) {
        return if (method == .GET) .list else .{ .err = .method_not_allowed };
    }
    if (std.mem.startsWith(u8, target, "/kv/")) {
        const key = Key.init(target["/kv/".len..]) orelse return .{ .err = .bad_request };
        const m = method orelse return .{ .err = .method_not_allowed };
        return switch (m) {
            .GET => .{ .get = key },
            .PUT => .{ .put = key },
            .DELETE => .{ .delete = key },
            else => .{ .err = .method_not_allowed },
        };
    }
    return .{ .err = .not_found };
}

const testing = std.testing;

fn expectErr(want: http.Status, got: Action) !void {
    try testing.expectEqual(want, got.err);
}

test resolve {
    try testing.expectEqual(.health, std.meta.activeTag(resolve(.GET, "/health")));
    try expectErr(.method_not_allowed, resolve(.POST, "/health"));
    try expectErr(.method_not_allowed, resolve(null, "/health"));
    try testing.expectEqual(.list, std.meta.activeTag(resolve(.GET, "/kv")));
    try expectErr(.method_not_allowed, resolve(.PUT, "/kv"));
    try testing.expectEqualStrings("a-B_9", resolve(.PUT, "/kv/a-B_9").put.slice());
    try testing.expectEqualStrings("x", resolve(.DELETE, "/kv/x").delete.slice());
    try expectErr(.method_not_allowed, resolve(.PATCH, "/kv/a"));
    try expectErr(.bad_request, resolve(.GET, "/kv/"));
    try expectErr(.bad_request, resolve(.GET, "/kv/a/b"));
    try expectErr(.bad_request, resolve(.GET, "/kv/bad.key"));
    try expectErr(.bad_request, resolve(.GET, "/kv/" ++ "a" ** 65));
    try testing.expectEqual(64, resolve(.GET, "/kv/" ++ "a" ** 64).get.len);
    try expectErr(.not_found, resolve(.GET, "/nope"));
    try expectErr(.not_found, resolve(.GET, "/"));
    try expectErr(.not_found, resolve(.GET, "/kvx"));
}
