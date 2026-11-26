//! The route table: maps request paths and methods to handlers.
//!
//! Each endpoint group lives in its own module under `api/`, so that groups
//! can be developed independently:
//!
//!   api/health.zig  GET /health
//!   api/notes.zig   POST /notes, GET /notes/{id}
//!   api/crud.zig    PUT /notes/{id}, DELETE /notes/{id}
//!   api/list.zig    GET /notes
//!   api/stats.zig   GET /stats, GET /tags

const std = @import("std");
const http = std.http;
const Context = @import("http/Context.zig");

const health = @import("api/health.zig");
const notes = @import("api/notes.zig");
const crud = @import("api/crud.zig");
const list = @import("api/list.zig");
const stats = @import("api/stats.zig");

pub const Handler = *const fn (ctx: *Context) Context.Error!void;

pub const Route = struct {
    /// Path segments separated by `/`; a `{name}` segment matches any
    /// non-empty segment and makes it available as `ctx.param("name")`.
    pattern: []const u8,
    handlers: std.enums.EnumFieldStruct(http.Method, ?Handler, @as(?Handler, null)),
};

pub const routes = [_]Route{
    .{ .pattern = "/health", .handlers = .{ .GET = health.get } },
    .{ .pattern = "/notes", .handlers = .{ .GET = list.list, .POST = notes.create } },
    .{ .pattern = "/notes/{id}", .handlers = .{ .GET = notes.get, .PUT = crud.update, .DELETE = crud.remove } },
    .{ .pattern = "/stats", .handlers = .{ .GET = stats.stats } },
    .{ .pattern = "/tags", .handlers = .{ .GET = stats.tags } },
};

const max_params = 4;

/// Runs the handler for the request's path and method, or answers 404
/// (unknown path) or 405 (known path, unsupported method).
pub fn dispatch(ctx: *Context) Context.Error!void {
    var params: [max_params]Context.Param = undefined;
    inline for (routes) |route| {
        if (match(route.pattern, ctx.path, &params)) |n| {
            ctx.params = params[0..n];
            const handlers = comptime std.EnumArray(http.Method, ?Handler).initDefault(@as(?Handler, null), route.handlers);
            if (handlers.get(ctx.method)) |handler| return handler(ctx);
            const allow = comptime allowHeader(handlers);
            try ctx.respond(.method_not_allowed, "{\"error\":\"method not allowed\"}", &.{
                .{ .name = "content-type", .value = "application/json" },
                .{ .name = "allow", .value = allow },
            });
            return;
        }
    }
    try ctx.sendError(.not_found, "not found");
}

fn allowHeader(comptime handlers: std.EnumArray(http.Method, ?Handler)) []const u8 {
    var allow: []const u8 = "";
    for (std.enums.values(http.Method)) |method| {
        if (handlers.get(method) == null) continue;
        allow = allow ++ (if (allow.len == 0) "" else ", ") ++ @tagName(method);
    }
    return allow;
}

/// Matches `path` against `pattern`, storing `{name}` captures in `params`.
/// Returns the number of captures, or null if the path does not match.
fn match(comptime pattern: []const u8, path: []const u8, params: *[max_params]Context.Param) ?usize {
    var n: usize = 0;
    var want = std.mem.splitScalar(u8, pattern, '/');
    var got = std.mem.splitScalar(u8, path, '/');
    while (want.next()) |segment| {
        const actual = got.next() orelse return null;
        if (segment.len > 2 and segment[0] == '{' and segment[segment.len - 1] == '}') {
            if (actual.len == 0) return null;
            params[n] = .{ .name = segment[1 .. segment.len - 1], .value = actual };
            n += 1;
        } else if (!std.mem.eql(u8, segment, actual)) {
            return null;
        }
    }
    if (got.next() != null) return null;
    return n;
}

test match {
    var params: [max_params]Context.Param = undefined;
    try std.testing.expectEqual(0, match("/notes", "/notes", &params));
    try std.testing.expectEqual(null, match("/notes", "/notes/", &params));
    try std.testing.expectEqual(null, match("/notes", "/note", &params));
    try std.testing.expectEqual(null, match("/notes", "/", &params));

    try std.testing.expectEqual(1, match("/notes/{id}", "/notes/42", &params));
    try std.testing.expectEqualStrings("id", params[0].name);
    try std.testing.expectEqualStrings("42", params[0].value);
    try std.testing.expectEqual(null, match("/notes/{id}", "/notes/", &params));
    try std.testing.expectEqual(null, match("/notes/{id}", "/notes", &params));
    try std.testing.expectEqual(null, match("/notes/{id}", "/notes/1/x", &params));
}

test allowHeader {
    const handlers = comptime std.EnumArray(http.Method, ?Handler).initDefault(@as(?Handler, null), routes[2].handlers);
    try std.testing.expectEqualStrings("GET, PUT, DELETE", comptime allowHeader(handlers));
}

test {
    _ = health;
    _ = notes;
    _ = crud;
    _ = list;
    _ = stats;
}
