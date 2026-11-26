//! Aggregate queries over all notes: the note count and per-tag counts.
//! Functions take a `sqlite.Db` obtained with `Store.acquire` and allocate
//! results in the given (request) arena.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sqlite = @import("sqlite.zig");

pub const Error = sqlite.Error || Allocator.Error;

/// The number of notes that have `tag`.
pub const TagCount = struct {
    tag: []const u8,
    count: i64,
};

pub const Order = enum {
    /// Tag ascending.
    by_tag,
    /// Count descending, then tag ascending.
    by_count,
};

/// The number of notes.
pub fn noteCount(db: sqlite.Db) sqlite.Error!i64 {
    var stmt = try db.prepare("SELECT count(*) FROM notes");
    defer stmt.deinit();
    if (!try stmt.step()) return error.Sqlite;
    return stmt.columnInt(0);
}

/// Every tag in use with the number of notes that have it. Tags of deleted
/// notes are gone with them (`ON DELETE CASCADE`), so they do not count.
pub fn tagCounts(db: sqlite.Db, arena: Allocator, order: Order) Error![]TagCount {
    const sql = switch (order) {
        .by_tag => "SELECT tag, count(*) FROM note_tags GROUP BY tag ORDER BY tag",
        .by_count => "SELECT tag, count(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag",
    };
    var stmt = try db.prepare(sql);
    defer stmt.deinit();
    var counts: std.ArrayList(TagCount) = .empty;
    while (try stmt.step()) {
        try counts.append(arena, .{
            .tag = try stmt.columnTextAlloc(arena, 0),
            .count = stmt.columnInt(1),
        });
    }
    return counts.toOwnedSlice(arena);
}

const testing = std.testing;
const notes = @import("notes.zig");

fn openTestDb() !sqlite.Db {
    const db = try sqlite.Db.open(":memory:", .{});
    errdefer db.close();
    try db.exec("PRAGMA foreign_keys = ON");
    try @import("schema.zig").migrate(db);
    return db;
}

fn expectCounts(expected: []const TagCount, actual: []const TagCount) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| {
        try testing.expectEqualStrings(e.tag, a.tag);
        try testing.expectEqual(e.count, a.count);
    }
}

test "an empty database has no notes and no tags" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(i64, 0), try noteCount(db));
    try testing.expectEqual(0, (try tagCounts(db, arena.allocator(), .by_tag)).len);
    try testing.expectEqual(0, (try tagCounts(db, arena.allocator(), .by_count)).len);
}

test "tags are counted per note and ordered" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes.insert(db, .{ .title = "a", .tags = &.{ "b", "c" } });
    _ = try notes.insert(db, .{ .title = "b", .tags = &.{ "a", "c" } });
    _ = try notes.insert(db, .{ .title = "c", .tags = &.{ "c", "z" } });
    _ = try notes.insert(db, .{ .title = "d" });

    try testing.expectEqual(@as(i64, 4), try noteCount(db));
    try expectCounts(&.{
        .{ .tag = "a", .count = 1 },
        .{ .tag = "b", .count = 1 },
        .{ .tag = "c", .count = 3 },
        .{ .tag = "z", .count = 1 },
    }, try tagCounts(db, arena.allocator(), .by_tag));
    try expectCounts(&.{
        .{ .tag = "c", .count = 3 },
        .{ .tag = "a", .count = 1 },
        .{ .tag = "b", .count = 1 },
        .{ .tag = "z", .count = 1 },
    }, try tagCounts(db, arena.allocator(), .by_count));
}

test "tags of deleted notes no longer count" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes.insert(db, .{ .title = "a", .tags = &.{ "x", "y" } });
    _ = try notes.insert(db, .{ .title = "b", .tags = &.{"x"} });
    try db.run("DELETE FROM notes WHERE id = ?", .{1});

    try testing.expectEqual(@as(i64, 1), try noteCount(db));
    try expectCounts(&.{.{ .tag = "x", .count = 1 }}, try tagCounts(db, arena.allocator(), .by_count));
}
