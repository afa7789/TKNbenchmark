//! Maps requests to responses against the store.
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const http = @import("http.zig");
const Store = @import("Store.zig");

pub const Response = struct {
    status: http.Status,
    content_type: ?[]const u8 = null,
    body: []const u8 = "",
    /// Store reference backing `body`; the caller releases it after sending.
    blob: ?*Store.Blob = null,

    fn empty(status: http.Status) Response {
        return .{ .status = status };
    }
};

/// Everything allocated for the response lives in `arena`.
pub fn handle(store: *Store, io: Io, arena: Allocator, req: http.Request) Allocator.Error!Response {
    const method = std.meta.stringToEnum(std.http.Method, req.method);
    const path = req.target;

    if (std.mem.eql(u8, path, "/health")) {
        if (method != .GET) return .empty(.method_not_allowed);
        return .{ .status = .ok, .content_type = "text/plain", .body = "ok" };
    }
    if (std.mem.eql(u8, path, "/kv")) {
        if (method != .GET) return .empty(.method_not_allowed);
        return .{ .status = .ok, .content_type = "application/json", .body = try listJson(store, io, arena) };
    }
    if (std.mem.startsWith(u8, path, "/kv/")) {
        const key = path["/kv/".len..];
        if (!isValidKey(key)) return .empty(.bad_request);
        return switch (method orelse return .empty(.method_not_allowed)) {
            .GET => if (store.get(io, key)) |blob|
                .{ .status = .ok, .content_type = "application/octet-stream", .body = blob.data, .blob = blob }
            else
                .empty(.not_found),
            .PUT => switch (try store.put(io, key, req.body)) {
                .created => .empty(.created),
                .replaced => .empty(.ok),
            },
            .DELETE => .empty(if (store.delete(io, key)) .no_content else .not_found),
            else => .empty(.method_not_allowed),
        };
    }
    return .empty(.not_found);
}

pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > Store.key_max) return false;
    for (key) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }
    return true;
}

/// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is needed.
fn listJson(store: *Store, io: Io, arena: Allocator) Allocator.Error![]const u8 {
    const keys = try store.keys(io, arena);
    var len: usize = 2;
    for (keys) |k| len += k.len + 3;

    var json: std.ArrayList(u8) = try .initCapacity(arena, len);
    json.appendAssumeCapacity('[');
    for (keys, 0..) |k, i| {
        if (i != 0) json.appendAssumeCapacity(',');
        json.appendAssumeCapacity('"');
        json.appendSliceAssumeCapacity(k);
        json.appendAssumeCapacity('"');
    }
    json.appendAssumeCapacity(']');
    return json.items;
}

test isValidKey {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("A-z_09"));
    try std.testing.expect(isValidKey("k" ** 64));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("k" ** 65));
    try std.testing.expect(!isValidKey("a/b"));
    try std.testing.expect(!isValidKey("bad.key"));
}

test "routing" {
    const io = std.testing.io;
    var store: Store = .init(std.testing.allocator);
    defer store.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const cases = [_]struct { []const u8, []const u8, []const u8, http.Status, []const u8 }{
        .{ "GET", "/health", "", .ok, "ok" },
        .{ "POST", "/health", "", .method_not_allowed, "" },
        .{ "GET", "/nope", "", .not_found, "" },
        .{ "GET", "/kv/", "", .bad_request, "" },
        .{ "GET", "/kv/a/b", "", .bad_request, "" },
        .{ "PUT", "/kv/b", "2", .created, "" },
        .{ "PUT", "/kv/a", "1", .created, "" },
        .{ "PUT", "/kv/a", "one", .ok, "" },
        .{ "GET", "/kv/a", "", .ok, "one" },
        .{ "PATCH", "/kv/a", "", .method_not_allowed, "" },
        .{ "BREW", "/kv/a", "", .method_not_allowed, "" },
        .{ "GET", "/kv", "", .ok, "[\"a\",\"b\"]" },
        .{ "DELETE", "/kv/a", "", .no_content, "" },
        .{ "DELETE", "/kv/a", "", .not_found, "" },
        .{ "GET", "/kv/a", "", .not_found, "" },
        .{ "POST", "/kv", "", .method_not_allowed, "" },
    };
    for (cases) |c| {
        const res = try handle(&store, io, arena, .{ .method = c[0], .target = c[1], .body = c[2] });
        defer if (res.blob) |b| store.release(b);
        try std.testing.expectEqual(c[3], res.status);
        try std.testing.expectEqualStrings(c[4], res.body);
    }
}
