//! Request and response types shared by the server, the router and the
//! handlers in `src/api/`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Store = @import("Store.zig");

pub const Request = struct {
    /// Freed when the response has been sent; allocate everything for the
    /// response here.
    arena: Allocator,
    store: *Store,
    method: std.http.Method,
    /// The target before any `?`, e.g. `/notes/7`. Not percent-decoded.
    path: []const u8,
    /// The raw query string after `?`, without it; empty if there is none.
    query: []const u8,
    /// The request body; empty for methods without one.
    body: []const u8,
};

pub const Response = struct {
    status: std.http.Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    /// Value of the `Allow` header, sent with 405 responses.
    allow: ?[]const u8 = null,
};

pub const json_content_type = "application/json";

/// A response whose body is `value` serialized as JSON.
pub fn json(arena: Allocator, status: std.http.Status, value: anytype) Allocator.Error!Response {
    return .{
        .status = status,
        .body = try std.json.Stringify.valueAlloc(arena, value, .{}),
        .content_type = json_content_type,
    };
}

/// A `{"error": message}` response.
pub fn jsonError(arena: Allocator, status: std.http.Status, message: []const u8) Allocator.Error!Response {
    return json(arena, status, .{ .@"error" = message });
}

pub fn text(status: std.http.Status, body: []const u8) Response {
    return .{ .status = status, .body = body, .content_type = "text/plain; charset=utf-8" };
}

pub const no_content: Response = .{ .status = .no_content };

test json {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const res = try jsonError(arena.allocator(), .bad_request, "bad \"input\"");
    try std.testing.expectEqual(std.http.Status.bad_request, res.status);
    try std.testing.expectEqualStrings("{\"error\":\"bad \\\"input\\\"\"}", res.body);
    try std.testing.expectEqualStrings(json_content_type, res.content_type.?);
}
