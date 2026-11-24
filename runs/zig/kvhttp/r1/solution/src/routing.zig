//! Maps a request method and target to an API operation, or to the error
//! status that must be returned instead. Pure; no I/O.

const std = @import("std");
const Status = std.http.Status;

pub const max_key_len = 64;

/// A validated key, copied out of the request head (whose memory is
/// invalidated once the body is read).
pub const Key = struct {
    buf: [max_key_len]u8,
    len: u8,

    pub fn parse(s: []const u8) ?Key {
        if (s.len == 0 or s.len > max_key_len) return null;
        for (s) |c| if (!isKeyChar(c)) return null;
        var k: Key = .{ .buf = undefined, .len = @intCast(s.len) };
        @memcpy(k.buf[0..s.len], s);
        return k;
    }

    pub fn slice(k: *const Key) []const u8 {
        return k.buf[0..k.len];
    }

    fn isKeyChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
    }
};

pub const Route = union(enum) {
    health,
    list,
    get: Key,
    put: Key,
    delete: Key,
};

pub const Resolution = union(enum) {
    route: Route,
    /// The request cannot be served; respond with this status.
    reject: Status,
};

/// `method` is the raw method token, so unknown methods route uniformly.
pub fn resolve(method: []const u8, target: []const u8) Resolution {
    const eql = std.mem.eql;
    const kv_prefix = "/kv/";

    if (eql(u8, target, "/health")) {
        return if (eql(u8, method, "GET")) .{ .route = .health } else .{ .reject = .method_not_allowed };
    }
    if (eql(u8, target, "/kv")) {
        return if (eql(u8, method, "GET")) .{ .route = .list } else .{ .reject = .method_not_allowed };
    }
    if (std.mem.startsWith(u8, target, kv_prefix)) {
        const key = Key.parse(target[kv_prefix.len..]) orelse return .{ .reject = .bad_request };
        if (eql(u8, method, "GET")) return .{ .route = .{ .get = key } };
        if (eql(u8, method, "PUT")) return .{ .route = .{ .put = key } };
        if (eql(u8, method, "DELETE")) return .{ .route = .{ .delete = key } };
        return .{ .reject = .method_not_allowed };
    }
    return .{ .reject = .not_found };
}

const testing = std.testing;

fn expectReject(want: Status, method: []const u8, target: []const u8) !void {
    try testing.expectEqual(Resolution{ .reject = want }, resolve(method, target));
}

fn expectKeyRoute(comptime tag: std.meta.Tag(Route), method: []const u8, target: []const u8, key: []const u8) !void {
    const res = resolve(method, target);
    try testing.expect(res == .route and res.route == tag);
    try testing.expectEqualStrings(key, @field(res.route, @tagName(tag)).slice());
}

test "static routes" {
    try testing.expectEqual(Resolution{ .route = .health }, resolve("GET", "/health"));
    try testing.expectEqual(Resolution{ .route = .list }, resolve("GET", "/kv"));
    try expectReject(.method_not_allowed, "POST", "/health");
    try expectReject(.method_not_allowed, "HEAD", "/health");
    try expectReject(.method_not_allowed, "PUT", "/kv");
    try expectReject(.method_not_allowed, "FROB", "/kv");
}

test "key routes" {
    try expectKeyRoute(.get, "GET", "/kv/a", "a");
    try expectKeyRoute(.put, "PUT", "/kv/A-z_09", "A-z_09");
    try expectKeyRoute(.delete, "DELETE", "/kv/x", "x");
    try expectKeyRoute(.get, "GET", "/kv/" ++ "k" ** 64, "k" ** 64);
    try expectReject(.method_not_allowed, "PATCH", "/kv/a");
    try expectReject(.method_not_allowed, "POST", "/kv/a");
}

test "invalid keys" {
    try expectReject(.bad_request, "GET", "/kv/");
    try expectReject(.bad_request, "GET", "/kv/bad.key");
    try expectReject(.bad_request, "GET", "/kv/a/b");
    try expectReject(.bad_request, "PUT", "/kv/" ++ "k" ** 65);
    try expectReject(.bad_request, "GET", "/kv/%41");
    try expectReject(.bad_request, "PATCH", "/kv/a b");
}

test "unknown paths" {
    try expectReject(.not_found, "GET", "/");
    try expectReject(.not_found, "GET", "/nope");
    try expectReject(.not_found, "GET", "/kvx");
    try expectReject(.not_found, "GET", "/health/");
    try expectReject(.not_found, "POST", "/kv2/a");
}
