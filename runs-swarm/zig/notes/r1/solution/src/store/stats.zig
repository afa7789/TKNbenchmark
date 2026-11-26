//! Aggregate queries over notes and tags for `GET /stats` and `GET /tags`.
//!
//! A tag counts the notes that have it. Tags of deleted notes are removed with
//! the note (`ON DELETE CASCADE`), so they never count.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sqlite = @import("../db/sqlite.zig");

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

pub const Summary = struct {
    notes: i64,
    /// Ordered by tag ascending.
    tags: []const TagCount,
};

/// The number of notes and the count of every tag, read from one snapshot so
/// that both agree.
pub fn summary(conn: sqlite.Conn, arena: Allocator) !Summary {
    try conn.begin(.deferred);
    defer conn.rollback();

    return .{
        .notes = try noteCount(conn),
        .tags = try tagCounts(conn, arena, .by_tag),
    };
}

pub fn noteCount(conn: sqlite.Conn) !i64 {
    var stmt = try conn.prepare("SELECT count(*) FROM notes");
    defer stmt.finalize();
    _ = try stmt.step();
    return stmt.columnInt(0);
}

/// Every tag in use with the number of notes that have it. Strings are copied
/// into `arena`.
pub fn tagCounts(conn: sqlite.Conn, arena: Allocator, order: Order) ![]const TagCount {
    // `note_tags` has one row per (note, tag), so `count(*)` counts notes; the
    // `(tag, note_id)` index serves the grouping.
    const sql = switch (order) {
        .by_tag => "SELECT tag, count(*) FROM note_tags GROUP BY tag ORDER BY tag",
        .by_count => "SELECT tag, count(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag",
    };
    var stmt = try conn.prepare(sql);
    defer stmt.finalize();

    var counts: std.ArrayList(TagCount) = .empty;
    while (try stmt.step()) {
        try counts.append(arena, .{
            .tag = try stmt.columnTextDupe(arena, 0),
            .count = stmt.columnInt(1),
        });
    }
    return counts.toOwnedSlice(arena);
}

const testing = std.testing;
const notes = @import("notes.zig");

fn expectCounts(expected: []const TagCount, actual: []const TagCount) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| {
        try testing.expectEqualStrings(want.tag, got.tag);
        try testing.expectEqual(want.count, got.count);
    }
}

test "empty database" {
    const conn = try notes.openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const s = try summary(conn, arena.allocator());
    try testing.expectEqual(0, s.notes);
    try testing.expectEqual(0, s.tags.len);
    try testing.expectEqual(0, (try tagCounts(conn, arena.allocator(), .by_count)).len);
}

test "tag counts in both orders, ignoring deleted notes" {
    const conn = try notes.openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes.create(conn, .{ .title = "1", .tags = &.{ "b", "c" } });
    _ = try notes.create(conn, .{ .title = "2", .tags = &.{ "a", "c" } });
    _ = try notes.create(conn, .{ .title = "3", .tags = &.{ "b", "c" } });
    const gone = try notes.create(conn, .{ .title = "4", .tags = &.{ "a", "d" } });
    _ = try notes.create(conn, .{ .title = "5" });
    try conn.exec("DELETE FROM notes WHERE id = ?", .{gone.id});

    const s = try summary(conn, arena.allocator());
    try testing.expectEqual(4, s.notes);
    try expectCounts(&.{
        .{ .tag = "a", .count = 1 },
        .{ .tag = "b", .count = 2 },
        .{ .tag = "c", .count = 3 },
    }, s.tags);

    try expectCounts(&.{
        .{ .tag = "c", .count = 3 },
        .{ .tag = "b", .count = 2 },
        .{ .tag = "a", .count = 1 },
    }, try tagCounts(conn, arena.allocator(), .by_count));
}

test "equal counts are ordered by tag" {
    const conn = try notes.openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes.create(conn, .{ .title = "1", .tags = &.{ "a-2", "a1", "z" } });
    _ = try notes.create(conn, .{ .title = "2", .tags = &.{"z"} });

    try expectCounts(&.{
        .{ .tag = "z", .count = 2 },
        .{ .tag = "a-2", .count = 1 },
        .{ .tag = "a1", .count = 1 },
    }, try tagCounts(conn, arena.allocator(), .by_count));
}
