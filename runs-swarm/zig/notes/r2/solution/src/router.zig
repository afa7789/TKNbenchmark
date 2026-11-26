//! Maps a request to its handler. Every route of the service is declared
//! here, so adding or completing an endpoint only touches its file in
//! `src/api/`.
//!
//! | Route          | Methods            | Handlers                          |
//! |----------------|--------------------|-----------------------------------|
//! | `/health`      | GET                | `api/health.zig`                  |
//! | `/notes`       | GET, POST          | `api/list.zig`, `api/notes.zig`   |
//! | `/notes/{id}`  | GET, PUT, DELETE   | `api/notes.zig`, `api/crud.zig`   |
//! | `/stats`       | GET                | `api/stats.zig`                   |
//! | `/tags`        | GET                | `api/stats.zig`                   |

const std = @import("std");
const web = @import("web.zig");
const health = @import("api/health.zig");
const notes = @import("api/notes.zig");
const crud = @import("api/crud.zig");
const list = @import("api/list.zig");
const stats = @import("api/stats.zig");

const Request = web.Request;
const Response = web.Response;

pub const Route = union(enum) {
    health,
    notes,
    /// `/notes/{segment}`; the segment is not validated yet.
    note: []const u8,
    stats,
    tags,
};

pub fn match(path: []const u8) ?Route {
    if (std.mem.eql(u8, path, "/health")) return .health;
    if (std.mem.eql(u8, path, "/notes")) return .notes;
    if (std.mem.eql(u8, path, "/stats")) return .stats;
    if (std.mem.eql(u8, path, "/tags")) return .tags;
    if (std.mem.startsWith(u8, path, "/notes/")) {
        const segment = path["/notes/".len..];
        if (segment.len > 0 and std.mem.indexOfScalar(u8, segment, '/') == null) return .{ .note = segment };
    }
    return null;
}

pub fn dispatch(req: *Request) !Response {
    const route = match(req.path) orelse return notFound(req);
    switch (route) {
        .health => return switch (req.method) {
            .GET, .HEAD => health.get(req),
            else => methodNotAllowed(req, "GET"),
        },
        .notes => return switch (req.method) {
            .GET, .HEAD => list.list(req),
            .POST => notes.create(req),
            else => methodNotAllowed(req, "GET, POST"),
        },
        .note => |segment| {
            const allow = "GET, PUT, DELETE";
            switch (req.method) {
                .GET, .HEAD, .PUT, .DELETE => {},
                else => return methodNotAllowed(req, allow),
            }
            const id = parseId(segment) orelse return web.jsonError(req.arena, .not_found, "note not found");
            return switch (req.method) {
                .GET, .HEAD => notes.show(req, id),
                .PUT => crud.update(req, id),
                .DELETE => crud.remove(req, id),
                else => unreachable,
            };
        },
        .stats => return switch (req.method) {
            .GET, .HEAD => stats.stats(req),
            else => methodNotAllowed(req, "GET"),
        },
        .tags => return switch (req.method) {
            .GET, .HEAD => stats.tags(req),
            else => methodNotAllowed(req, "GET"),
        },
    }
}

/// A note id: a positive decimal integer, digits only.
pub fn parseId(segment: []const u8) ?i64 {
    for (segment) |ch| if (!std.ascii.isDigit(ch)) return null;
    const id = std.fmt.parseInt(i64, segment, 10) catch return null;
    return if (id > 0) id else null;
}

fn notFound(req: *Request) !Response {
    return web.jsonError(req.arena, .not_found, "not found");
}

fn methodNotAllowed(req: *Request, allow: []const u8) !Response {
    var res = try web.jsonError(req.arena, .method_not_allowed, "method not allowed");
    res.allow = allow;
    return res;
}

test match {
    try std.testing.expectEqual(Route.health, match("/health").?);
    try std.testing.expectEqual(Route.notes, match("/notes").?);
    try std.testing.expectEqualStrings("12", match("/notes/12").?.note);
    try std.testing.expectEqual(null, match("/notes/"));
    try std.testing.expectEqual(null, match("/notes/1/x"));
    try std.testing.expectEqual(null, match("/health/"));
    try std.testing.expectEqual(null, match("/nope"));
}

test parseId {
    try std.testing.expectEqual(@as(?i64, 7), parseId("7"));
    try std.testing.expectEqual(@as(?i64, 9223372036854775807), parseId("9223372036854775807"));
    try std.testing.expectEqual(null, parseId("0"));
    try std.testing.expectEqual(null, parseId("-1"));
    try std.testing.expectEqual(null, parseId("+1"));
    try std.testing.expectEqual(null, parseId("abc"));
    try std.testing.expectEqual(null, parseId("1.0"));
    try std.testing.expectEqual(null, parseId("9223372036854775808"));
}
