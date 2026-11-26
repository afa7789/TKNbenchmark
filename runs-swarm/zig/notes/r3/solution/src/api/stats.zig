//! GET /stats and GET /tags.

const std = @import("std");
const Context = @import("../http/Context.zig");
const stats_db = @import("../db/stats.zig");
const TagCount = stats_db.TagCount;

/// GET /stats: `{"notes": <count>, "tags": {"<tag>": <count>, ...}}`.
pub fn stats(ctx: *Context) Context.Error!void {
    const notes: i64, const counts: []const TagCount = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk .{ try stats_db.noteCount(db), try stats_db.tagCounts(db, ctx.arena, .by_tag) };
    };
    try ctx.sendJson(.ok, .{ .notes = notes, .tags = TagMap{ .counts = counts } });
}

/// GET /tags: `{"tags": [{"tag": "<tag>", "count": <n>}, ...]}`, ordered by
/// count descending, then tag ascending.
pub fn tags(ctx: *Context) Context.Error!void {
    const counts = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk try stats_db.tagCounts(db, ctx.arena, .by_count);
    };
    try ctx.sendJson(.ok, .{ .tags = counts });
}

/// Serializes tag counts as a JSON object mapping each tag to its count.
const TagMap = struct {
    counts: []const TagCount,

    pub fn jsonStringify(map: TagMap, jws: anytype) !void {
        try jws.beginObject();
        for (map.counts) |c| {
            try jws.objectField(c.tag);
            try jws.write(c.count);
        }
        try jws.endObject();
    }
};

test TagMap {
    const gpa = std.testing.allocator;

    const empty = try std.json.Stringify.valueAlloc(gpa, .{ .tags = TagMap{ .counts = &.{} } }, .{});
    defer gpa.free(empty);
    try std.testing.expectEqualStrings("{\"tags\":{}}", empty);

    const map: TagMap = .{ .counts = &.{ .{ .tag = "a", .count = 2 }, .{ .tag = "b-1", .count = 1 } } };
    const json = try std.json.Stringify.valueAlloc(gpa, map, .{});
    defer gpa.free(json);
    try std.testing.expectEqualStrings("{\"a\":2,\"b-1\":1}", json);
}

test {
    _ = stats_db;
}
