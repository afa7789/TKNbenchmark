//! Maps parsed HTTP requests onto key-value store operations.

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;

const http = @import("http.zig");
const Store = @import("Store.zig");

pub const max_key_len = 64;
pub const max_value_len = 1024 * 1024;

pub const Response = struct {
    status: http.Status,
    content_type: ?[]const u8 = null,
    body: []const u8 = "",

    pub fn empty(status: http.Status) Response {
        return .{ .status = status };
    }
};

/// Handles one request. Response bytes are allocated with `arena`, which must
/// outlive the response.
pub fn handle(store: *Store, io: Io, arena: Allocator, req: http.Request, body: []const u8) Response {
    return route(store, io, arena, req, body) catch |err| switch (err) {
        error.OutOfMemory => .empty(.internal_server_error),
    };
}

fn route(store: *Store, io: Io, arena: Allocator, req: http.Request, body: []const u8) Allocator.Error!Response {
    const path = req.target;
    const method = Method.parse(req.method);

    if (mem.eql(u8, path, "/health")) {
        if (method != .GET) return .empty(.method_not_allowed);
        return .{ .status = .ok, .content_type = "text/plain", .body = "ok" };
    }
    if (mem.eql(u8, path, "/kv")) {
        if (method != .GET) return .empty(.method_not_allowed);
        return .{
            .status = .ok,
            .content_type = "application/json",
            .body = try keysJson(arena, try store.sortedKeys(io, arena)),
        };
    }
    if (mem.startsWith(u8, path, "/kv/")) {
        const key = path["/kv/".len..];
        if (!isValidKey(key)) return .empty(.bad_request);
        return switch (method) {
            .GET => if (try store.get(io, arena, key)) |value|
                .{ .status = .ok, .content_type = "application/octet-stream", .body = value }
            else
                .empty(.not_found),
            .PUT => switch (try store.put(io, key, body)) {
                .created => .empty(.created),
                .replaced => .empty(.ok),
            },
            .DELETE => .empty(if (store.delete(io, key)) .no_content else .not_found),
            .other => .empty(.method_not_allowed),
        };
    }
    return .empty(.not_found);
}

const Method = enum {
    GET,
    PUT,
    DELETE,
    other,

    fn parse(s: []const u8) Method {
        // Methods are case-sensitive (RFC 9110 section 9.1).
        return std.meta.stringToEnum(Method, s) orelse .other;
    }
};

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len < 1 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

/// Valid keys never need JSON escaping, so they are written verbatim.
fn keysJson(arena: Allocator, keys: []const []const u8) Allocator.Error![]u8 {
    var out: Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    w.writeByte('[') catch return error.OutOfMemory;
    for (keys, 0..) |key, i| {
        if (i != 0) w.writeByte(',') catch return error.OutOfMemory;
        w.print("\"{s}\"", .{key}) catch return error.OutOfMemory;
    }
    w.writeByte(']') catch return error.OutOfMemory;
    return out.toOwnedSlice();
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
}

test handle {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const Case = struct { []const u8, []const u8, []const u8, http.Status };
    const cases = [_]Case{
        .{ "GET", "/health", "", .ok },
        .{ "POST", "/health", "", .method_not_allowed },
        .{ "PUT", "/kv/b", "2", .created },
        .{ "PUT", "/kv/a", "1", .created },
        .{ "PUT", "/kv/a", "one", .ok },
        .{ "GET", "/kv/a", "", .ok },
        .{ "PATCH", "/kv/a", "", .method_not_allowed },
        .{ "GET", "/kv/", "", .bad_request },
        .{ "GET", "/kv/a/b", "", .bad_request },
        .{ "GET", "/nope", "", .not_found },
        .{ "POST", "/kv", "", .method_not_allowed },
        .{ "DELETE", "/kv/b", "", .no_content },
        .{ "DELETE", "/kv/b", "", .not_found },
        .{ "GET", "/kv/b", "", .not_found },
    };
    for (cases) |c| {
        const res = handle(&store, io, arena, .{ .method = c[0], .target = c[1] }, c[2]);
        try testing.expectEqual(c[3], res.status);
    }

    _ = try store.put(io, "c", "3");
    const list = handle(&store, io, arena, .{ .method = "GET", .target = "/kv" }, "");
    try testing.expectEqualStrings("[\"a\",\"c\"]", list.body);
    const get = handle(&store, io, arena, .{ .method = "GET", .target = "/kv/a" }, "");
    try testing.expectEqualStrings("one", get.body);
}
