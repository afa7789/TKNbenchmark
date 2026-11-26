//! Data access for `GET /stats` and `GET /tags`.
//!
//! Tags live in `note_tags (note_id, tag)`, indexed by `(tag, note_id)`.
//! Deleting a note cascades to its tags, so counting `note_tags` rows only
//! ever counts tags of existing notes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Store = @import("../Store.zig");
const sqlite = @import("../sqlite.zig");
const notes = @import("notes.zig");

/// How many notes carry `tag`.
pub const TagCount = struct {
    tag: []const u8,
    count: i64,
};

pub const Stats = struct {
    /// Number of notes.
    notes: i64,
    /// Every tag in use, ordered by tag ascending.
    tags: []const TagCount,
};

pub const TagOrder = enum {
    /// Tag ascending.
    tag,
    /// Count descending, then tag ascending.
    count,
};

/// The number of notes and the per-tag counts, read under one lock so they
/// are consistent with each other.
pub fn stats(store: *Store, arena: Allocator) !Stats {
    const db = try store.acquire();
    defer store.release();
    return .{
        .notes = try countNotes(db),
        .tags = try tagCounts(db, arena, .tag),
    };
}

/// Every tag in use with the number of notes carrying it, in `order`.
pub fn tags(store: *Store, arena: Allocator, order: TagOrder) ![]const TagCount {
    const db = try store.acquire();
    defer store.release();
    return tagCounts(db, arena, order);
}

fn countNotes(db: sqlite.Db) !i64 {
    const stmt = try db.prepare("SELECT count(*) FROM notes");
    defer stmt.finalize();
    _ = try stmt.step();
    return stmt.int(0);
}

/// Expects the caller to hold the store lock.
fn tagCounts(db: sqlite.Db, arena: Allocator, order: TagOrder) ![]const TagCount {
    const select = "SELECT tag, count(*) AS n FROM note_tags GROUP BY tag ORDER BY ";
    const sql = switch (order) {
        .tag => select ++ "tag",
        .count => select ++ "n DESC, tag",
    };
    const stmt = try db.prepare(sql);
    defer stmt.finalize();
    var result: std.ArrayList(TagCount) = .empty;
    while (try stmt.step()) {
        try result.append(arena, .{ .tag = try stmt.textAlloc(arena, 0), .count = stmt.int(1) });
    }
    return result.toOwnedSlice(arena);
}

const testing = std.testing;

test "stats and tags of an empty store" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try testing.expectEqualDeep(Stats{ .notes = 0, .tags = &.{} }, try stats(&store, a));
    try testing.expectEqual(0, (try tags(&store, a, .count)).len);
}

test "tags are counted per note and ordered" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try notes.create(&store, .{ .title = "1", .tags = &.{ "b", "c" } });
    _ = try notes.create(&store, .{ .title = "2", .tags = &.{ "a", "c" } });
    _ = try notes.create(&store, .{ .title = "3", .tags = &.{"b"} });
    const deleted = try notes.create(&store, .{ .title = "4", .tags = &.{ "a", "z" } });
    _ = try notes.create(&store, .{ .title = "5" });
    {
        const db = try store.acquire();
        defer store.release();
        try db.run("DELETE FROM notes WHERE id = ?1", .{deleted.id});
    }

    try testing.expectEqualDeep(Stats{ .notes = 4, .tags = &.{
        .{ .tag = "a", .count = 1 },
        .{ .tag = "b", .count = 2 },
        .{ .tag = "c", .count = 2 },
    } }, try stats(&store, a));

    try testing.expectEqualDeep(@as([]const TagCount, &.{
        .{ .tag = "b", .count = 2 },
        .{ .tag = "c", .count = 2 },
        .{ .tag = "a", .count = 1 },
    }), try tags(&store, a, .count));
}
