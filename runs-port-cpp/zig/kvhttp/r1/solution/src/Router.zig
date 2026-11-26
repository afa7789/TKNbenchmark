//! Maps requests onto the key/value API described in SPEC.md.

const Router = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const http = @import("http.zig");
const KvStore = @import("KvStore.zig");

store: *KvStore,

const kv_prefix = "/kv/";
const max_key_len = 64;

pub const Reply = struct {
    response: http.Response,
    /// Stored value backing `response.body`, if any. The holder must call
    /// `release` once the response has been written.
    value: ?*KvStore.Value = null,

    fn of(response: http.Response) Reply {
        return .{ .response = response };
    }

    pub fn release(reply: Reply, gpa: Allocator) void {
        if (reply.value) |value| value.release(gpa);
    }
};

/// Handles `request`. Temporary allocations come from `arena`, which must
/// outlive the reply. On a successful PUT the body is moved into the store
/// and `request.body` is left empty.
pub fn handle(router: Router, io: Io, arena: Allocator, request: *http.Request) Allocator.Error!Reply {
    const path = request.target;
    const method = request.method;

    if (std.mem.eql(u8, path, "/health")) {
        if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed("GET");
        return .of(.text(.ok, "ok"));
    }
    if (std.mem.eql(u8, path, "/kv")) {
        if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed("GET");
        return router.listKeys(io, arena);
    }
    if (std.mem.startsWith(u8, path, kv_prefix)) {
        const key = path[kv_prefix.len..];
        if (!isValidKey(key)) return .of(.empty(.bad_request));
        return router.handleKey(io, request, key);
    }
    return .of(.empty(.not_found));
}

fn handleKey(router: Router, io: Io, request: *http.Request, key: []const u8) Allocator.Error!Reply {
    const store = router.store;
    const method = request.method;

    if (std.mem.eql(u8, method, "GET")) {
        const value = store.get(io, key) orelse return .of(.empty(.not_found));
        return .{
            .response = .{ .status = .ok, .content_type = "application/octet-stream", .body = value.bytes },
            .value = value,
        };
    }
    if (std.mem.eql(u8, method, "PUT")) {
        const created = try store.put(io, key, request.body);
        request.body = &.{};
        return .of(.empty(if (created) .created else .ok));
    }
    if (std.mem.eql(u8, method, "DELETE")) {
        return .of(.empty(if (store.remove(io, key)) .no_content else .not_found));
    }
    return methodNotAllowed("GET, PUT, DELETE");
}

fn listKeys(router: Router, io: Io, arena: Allocator) Allocator.Error!Reply {
    const keys = try router.store.sortedKeys(io, arena);

    // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
    var len: usize = 2 + (keys.len -| 1); // brackets and commas
    for (keys) |key| len += key.len + 2;

    var json: std.ArrayList(u8) = try .initCapacity(arena, len);
    json.appendAssumeCapacity('[');
    for (keys, 0..) |key, i| {
        if (i != 0) json.appendAssumeCapacity(',');
        json.appendAssumeCapacity('"');
        json.appendSliceAssumeCapacity(key);
        json.appendAssumeCapacity('"');
    }
    json.appendAssumeCapacity(']');

    return .of(.{ .status = .ok, .content_type = "application/json", .body = json.items });
}

fn methodNotAllowed(allow: []const u8) Reply {
    return .of(.{ .status = .method_not_allowed, .allow = allow });
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

// ---------------------------------------------------------------- tests

const testing = std.testing;

test isValidKey {
    try testing.expect(isValidKey("a"));
    try testing.expect(isValidKey("A-z_09"));
    try testing.expect(isValidKey("k" ** 64));
    try testing.expect(!isValidKey(""));
    try testing.expect(!isValidKey("k" ** 65));
    try testing.expect(!isValidKey("a/b"));
    try testing.expect(!isValidKey("bad.key"));
    try testing.expect(!isValidKey("%41"));
}

fn expectStatus(router: Router, status: http.Status, method: []const u8, target: []const u8, body: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var request: http.Request = .{ .method = method, .target = target, .body = try testing.allocator.dupe(u8, body) };
    defer testing.allocator.free(request.body);
    const reply = try router.handle(testing.io, arena.allocator(), &request);
    defer reply.release(testing.allocator);
    try testing.expectEqual(status, reply.response.status);
}

test "routes" {
    var store: KvStore = .init(testing.allocator);
    defer store.deinit();
    const router: Router = .{ .store = &store };

    try expectStatus(router, .ok, "GET", "/health", "");
    try expectStatus(router, .method_not_allowed, "POST", "/health", "");
    try expectStatus(router, .not_found, "GET", "/nope", "");
    try expectStatus(router, .bad_request, "GET", "/kv/", "");
    try expectStatus(router, .bad_request, "GET", "/kv/a/b", "");
    try expectStatus(router, .created, "PUT", "/kv/a", "1");
    try expectStatus(router, .ok, "PUT", "/kv/a", "2");
    try expectStatus(router, .ok, "GET", "/kv/a", "");
    try expectStatus(router, .method_not_allowed, "PATCH", "/kv/a", "");
    try expectStatus(router, .method_not_allowed, "DELETE", "/kv", "");
    try expectStatus(router, .no_content, "DELETE", "/kv/a", "");
    try expectStatus(router, .not_found, "DELETE", "/kv/a", "");
    try expectStatus(router, .not_found, "GET", "/kv/a", "");
}

test "list keys as JSON" {
    var store: KvStore = .init(testing.allocator);
    defer store.deinit();
    const router: Router = .{ .store = &store };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var request: http.Request = .{ .method = "GET", .target = "/kv", .body = &.{} };

    try testing.expectEqualStrings("[]", (try router.handle(testing.io, arena.allocator(), &request)).response.body);
    _ = try store.put(testing.io, "b", try testing.allocator.dupe(u8, "2"));
    _ = try store.put(testing.io, "a", try testing.allocator.dupe(u8, "1"));
    try testing.expectEqualStrings("[\"a\",\"b\"]", (try router.handle(testing.io, arena.allocator(), &request)).response.body);
}
