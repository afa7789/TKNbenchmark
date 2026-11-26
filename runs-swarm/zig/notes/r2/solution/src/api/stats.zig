//! `GET /stats` and `GET /tags`.

const std = @import("std");
const web = @import("../web.zig");
const store = @import("../store/stats.zig");

/// `GET /stats`: 200 and `{"notes": <count>, "tags": {"<tag>": <count>, ...}}`.
pub fn stats(req: *web.Request) !web.Response {
    const result = try store.stats(req.store, req.arena);
    return web.json(req.arena, .ok, .{
        .notes = result.notes,
        .tags = TagObject{ .counts = result.tags },
    });
}

/// `GET /tags`: 200 and `{"tags": [{"tag": "<tag>", "count": <n>}, ...]}`
/// ordered by count descending, then tag ascending.
pub fn tags(req: *web.Request) !web.Response {
    const counts = try store.tags(req.store, req.arena, .count);
    return web.json(req.arena, .ok, .{ .tags = counts });
}

/// Serializes tag counts as a JSON object mapping each tag to its count.
const TagObject = struct {
    counts: []const store.TagCount,

    pub fn jsonStringify(self: TagObject, jw: anytype) !void {
        try jw.beginObject();
        for (self.counts) |entry| {
            try jw.objectField(entry.tag);
            try jw.write(entry.count);
        }
        try jw.endObject();
    }
};

test TagObject {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const empty = try web.json(arena.allocator(), .ok, TagObject{ .counts = &.{} });
    try std.testing.expectEqualStrings("{}", empty.body);
    const res = try web.json(arena.allocator(), .ok, .{ .notes = 3, .tags = TagObject{ .counts = &.{
        .{ .tag = "x", .count = 2 },
        .{ .tag = "y", .count = 1 },
    } } });
    try std.testing.expectEqualStrings("{\"notes\":3,\"tags\":{\"x\":2,\"y\":1}}", res.body);
}
