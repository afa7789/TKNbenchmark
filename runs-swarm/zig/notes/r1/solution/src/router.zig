//! Maps request paths and methods to handlers.
//!
//! Every endpoint of the service is routed here already; the handlers live in
//! `handlers/`, one file per feature, so features can be built independently.

const std = @import("std");
const api = @import("api.zig");
const Response = api.Response;

const notes = @import("handlers/notes.zig");
const crud = @import("handlers/crud.zig");
const list = @import("handlers/list.zig");
const stats = @import("handlers/stats.zig");

pub const Route = union(enum) {
    health,
    /// `/notes`
    notes,
    /// `/notes/{id}` with a positive integer id.
    note: i64,
    stats,
    tags,

    /// Returns the route for `path`, or `null` for an unknown path (404).
    pub fn match(path: []const u8) ?Route {
        const simple = std.StaticStringMap(Route).initComptime(.{
            .{ "/health", .health },
            .{ "/notes", .notes },
            .{ "/stats", .stats },
            .{ "/tags", .tags },
        });
        if (simple.get(path)) |route| return route;

        const prefix = "/notes/";
        if (std.mem.startsWith(u8, path, prefix)) {
            const id = parseId(path[prefix.len..]) orelse return null;
            return .{ .note = id };
        }
        return null;
    }
};

/// Parses a note id: a positive decimal integer without sign. Anything else
/// cannot name a note.
fn parseId(text: []const u8) ?i64 {
    if (text.len == 0) return null;
    for (text) |ch| if (!std.ascii.isDigit(ch)) return null;
    const id = std.fmt.parseInt(i64, text, 10) catch return null;
    return if (id > 0) id else null;
}

pub fn dispatch(ctx: *const api.Context, req: api.Request) !Response {
    const route = Route.match(req.path) orelse return Response.notFound(ctx.arena);
    return switch (route) {
        .health => switch (req.method) {
            .GET, .HEAD => Response.text(.ok, "ok"),
            else => Response.methodNotAllowed(ctx.arena, "GET, HEAD"),
        },
        .notes => switch (req.method) {
            .GET, .HEAD => list.list(ctx, req),
            .POST => notes.create(ctx, req),
            else => Response.methodNotAllowed(ctx.arena, "GET, HEAD, POST"),
        },
        .note => |id| switch (req.method) {
            .GET, .HEAD => notes.get(ctx, id),
            .PUT => crud.update(ctx, id, req),
            .DELETE => crud.delete(ctx, id),
            else => Response.methodNotAllowed(ctx.arena, "GET, HEAD, PUT, DELETE"),
        },
        .stats => switch (req.method) {
            .GET, .HEAD => stats.stats(ctx),
            else => Response.methodNotAllowed(ctx.arena, "GET, HEAD"),
        },
        .tags => switch (req.method) {
            .GET, .HEAD => stats.tags(ctx),
            else => Response.methodNotAllowed(ctx.arena, "GET, HEAD"),
        },
    };
}

const testing = std.testing;
const TestEnv = @import("TestEnv.zig");

test "Route.match" {
    try testing.expectEqual(Route.health, Route.match("/health").?);
    try testing.expectEqual(Route.notes, Route.match("/notes").?);
    try testing.expectEqual(Route{ .note = 42 }, Route.match("/notes/42").?);
    try testing.expectEqual(Route{ .note = 7 }, Route.match("/notes/007").?);
    try testing.expectEqual(Route.stats, Route.match("/stats").?);
    try testing.expectEqual(Route.tags, Route.match("/tags").?);

    for ([_][]const u8{
        "",                            "/",          "/nope",     "/notes/",
        "/notes/abc",                  "/notes/0",   "/notes/-1", "/notes/+1",
        "/notes/1/",                   "/notes/1.0", "/health/",  "/notes/1/x",
        "/notes/99999999999999999999",
    }) |path| {
        try testing.expectEqual(null, Route.match(path));
    }
}

test "health" {
    var env = try TestEnv.init();
    defer env.deinit();
    const res = try env.request(.GET, "/health", "");
    try testing.expectEqual(.ok, res.status);
    try testing.expectEqual(.text, res.content_type);
    try testing.expectEqualStrings("ok", res.body);
}

test "unknown paths and methods" {
    var env = try TestEnv.init();
    defer env.deinit();
    try env.expect(.GET, "/nope", "", .not_found, "{\"error\":\"not found\"}");
    try env.expect(.GET, "/notes/0", "", .not_found, null);
    try env.expect(.DELETE, "/notes", "", .method_not_allowed, "{\"error\":\"method not allowed\"}");
    try env.expect(.POST, "/health", "", .method_not_allowed, null);
    try env.expect(.POST, "/notes/1", "", .method_not_allowed, null);
    try env.expect(.DELETE, "/stats", "", .method_not_allowed, null);
    try env.expect(.PUT, "/tags", "", .method_not_allowed, null);
}
