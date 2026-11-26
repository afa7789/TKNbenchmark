//! Test helper: a fresh in-memory database and a way to send requests through
//! the router without a socket.
//!
//!     var env = try TestEnv.init();
//!     defer env.deinit();
//!     try env.expect(.POST, "/notes", "{\"title\":\"a\"}", .created, null);

const std = @import("std");
const testing = std.testing;
const api = @import("api.zig");
const router = @import("router.zig");
const Pool = @import("db/Pool.zig");

const TestEnv = @This();

pool: Pool,
arena: std.heap.ArenaAllocator,

pub fn init() !TestEnv {
    // One connection: every `:memory:` connection is a separate database.
    return .{
        .pool = try Pool.init(testing.allocator, ":memory:", .{ .size = 1 }),
        .arena = .init(testing.allocator),
    };
}

pub fn deinit(env: *TestEnv) void {
    env.pool.deinit();
    env.arena.deinit();
}

/// Sends a request through the router. The response lives until `deinit`.
pub fn request(env: *TestEnv, method: api.Method, target: []const u8, body: []const u8) !api.Response {
    const ctx: api.Context = .{ .io = testing.io, .arena = env.arena.allocator(), .pool = &env.pool };
    return router.dispatch(&ctx, .init(method, target, body));
}

/// Sends a request and checks the status and, unless `expected_json` is null,
/// that the body is JSON equal to `expected_json` (ignoring formatting).
pub fn expect(
    env: *TestEnv,
    method: api.Method,
    target: []const u8,
    body: []const u8,
    status: api.Status,
    expected_json: ?[]const u8,
) !void {
    const res = try env.request(method, target, body);
    testing.expectEqual(status, res.status) catch |err| {
        std.debug.print("{t} {s}: unexpected status, body: {s}\n", .{ method, target, res.body });
        return err;
    };
    const want = expected_json orelse return;
    try testing.expectEqual(.json, res.content_type);
    try expectJsonEqual(env.arena.allocator(), want, res.body);
}

/// Compares two JSON documents by re-serializing both in a canonical form.
pub fn expectJsonEqual(arena: std.mem.Allocator, expected: []const u8, actual: []const u8) !void {
    const canonical_expected = try canonicalJson(arena, expected);
    const canonical_actual = canonicalJson(arena, actual) catch |err| {
        std.debug.print("response is not valid JSON: {s}\n", .{actual});
        return err;
    };
    try testing.expectEqualStrings(canonical_expected, canonical_actual);
}

fn canonicalJson(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{});
    return std.json.Stringify.valueAlloc(arena, value, .{});
}
