//! `GET /stats` and `GET /tags`.

const std = @import("std");
const api = @import("../api.zig");
const store = @import("../store/stats.zig");
const Response = api.Response;

/// 200 with `{"notes": <count>, "tags": {"<tag>": <count>, ...}}`.
pub fn stats(ctx: *const api.Context) !Response {
    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    const summary = try store.summary(conn, ctx.arena);
    return Response.json(ctx.arena, .ok, .{
        .notes = summary.notes,
        .tags = TagCountObject{ .counts = summary.tags },
    });
}

/// 200 with `{"tags": [{"tag": "<tag>", "count": <n>}, ...]}` ordered by count
/// descending, then tag ascending.
pub fn tags(ctx: *const api.Context) !Response {
    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    const counts = try store.tagCounts(conn, ctx.arena, .by_count);
    return Response.json(ctx.arena, .ok, .{ .tags = counts });
}

/// Serializes tag counts as a JSON object `{"<tag>": <count>, ...}`.
const TagCountObject = struct {
    counts: []const store.TagCount,

    pub fn jsonStringify(self: TagCountObject, jw: *std.json.Stringify) std.json.Stringify.Error!void {
        try jw.beginObject();
        for (self.counts) |entry| {
            try jw.objectField(entry.tag);
            try jw.write(entry.count);
        }
        try jw.endObject();
    }
};

const TestEnv = @import("../TestEnv.zig");

test "stats and tags of an empty store" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.GET, "/stats", "", .ok,
        \\{"notes":0,"tags":{}}
    );
    try env.expect(.GET, "/tags", "", .ok,
        \\{"tags":[]}
    );
}

test "stats and tags count notes per tag" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.POST, "/notes", "{\"title\":\"a\",\"tags\":[\"y\",\"x\"]}", .created, null);
    try env.expect(.POST, "/notes", "{\"title\":\"b\",\"tags\":[\"x\",\"x\"]}", .created, null);
    try env.expect(.POST, "/notes", "{\"title\":\"c\",\"tags\":[\"w\"]}", .created, null);
    try env.expect(.POST, "/notes", "{\"title\":\"d\"}", .created, null);

    try env.expect(.GET, "/stats", "", .ok,
        \\{"notes":4,"tags":{"w":1,"x":2,"y":1}}
    );
    try env.expect(.GET, "/tags", "", .ok,
        \\{"tags":[{"tag":"x","count":2},{"tag":"w","count":1},{"tag":"y","count":1}]}
    );
    // The query string does not change the result.
    try env.expect(.GET, "/tags?x=1", "", .ok,
        \\{"tags":[{"tag":"x","count":2},{"tag":"w","count":1},{"tag":"y","count":1}]}
    );
}
