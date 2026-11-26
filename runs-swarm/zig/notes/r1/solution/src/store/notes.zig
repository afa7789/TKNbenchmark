//! Data access for single notes: creating, loading, and the tag helpers that
//! other queries build on.
//!
//! Functions take a connection from `db.Pool`; returned strings are copied
//! into the caller's allocator (usually the request arena).

const std = @import("std");
const Allocator = std.mem.Allocator;
const sqlite = @import("../db/sqlite.zig");
const note = @import("../note.zig");
const Note = note.Note;

/// Inserts a note with its tags in one transaction and returns it.
pub fn create(conn: sqlite.Conn, input: note.Input) !Note {
    try conn.begin(.immediate);
    errdefer conn.rollback();

    try conn.exec("INSERT INTO notes (title, body) VALUES (?, ?)", .{ input.title, input.body });
    const id = conn.lastInsertRowId();
    try insertTags(conn, id, input.tags);
    try conn.commit();

    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

/// Loads the note with the given id, or returns `null` if there is none.
pub fn get(conn: sqlite.Conn, arena: Allocator, id: i64) !?Note {
    // Read the note and its tags from one snapshot.
    try conn.begin(.deferred);
    defer conn.rollback();

    var stmt = try conn.prepare("SELECT title, body FROM notes WHERE id = ?");
    defer stmt.finalize();
    try stmt.bindAll(.{id});
    if (!try stmt.step()) return null;

    return .{
        .id = id,
        .title = try stmt.columnTextDupe(arena, 0),
        .body = try stmt.columnTextDupe(arena, 1),
        .tags = try tagsOf(conn, arena, id),
    };
}

/// The tags of a note, sorted ascending.
pub fn tagsOf(conn: sqlite.Conn, arena: Allocator, id: i64) ![]const []const u8 {
    var stmt = try conn.prepare("SELECT tag FROM note_tags WHERE note_id = ? ORDER BY tag");
    defer stmt.finalize();
    try stmt.bindAll(.{id});

    var tags: std.ArrayList([]const u8) = .empty;
    while (try stmt.step()) try tags.append(arena, try stmt.columnTextDupe(arena, 0));
    return tags.toOwnedSlice(arena);
}

/// Adds tags to a note. `tags` must already be validated and free of
/// duplicates (see `note.parseInput`). Call inside a write transaction.
pub fn insertTags(conn: sqlite.Conn, id: i64, tags: []const []const u8) !void {
    if (tags.len == 0) return;
    var stmt = try conn.prepare("INSERT INTO note_tags (note_id, tag) VALUES (?, ?)");
    defer stmt.finalize();
    for (tags) |tag| {
        try stmt.bindAll(.{ id, tag });
        _ = try stmt.step();
        stmt.reset();
    }
}

const testing = std.testing;
const schema = @import("../db/schema.zig");

pub fn openTestDb() !sqlite.Conn {
    const conn = try sqlite.Conn.open(":memory:", .{});
    errdefer conn.close();
    try schema.migrate(conn);
    return conn;
}

test "create assigns increasing ids and get reads notes back" {
    const conn = try openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const first = try create(conn, .{ .title = "first" });
    const second = try create(conn, .{ .title = "second", .body = "text", .tags = &.{ "a", "b" } });
    try testing.expectEqual(1, first.id);
    try testing.expectEqual(2, second.id);

    const loaded = (try get(conn, arena.allocator(), 2)).?;
    try testing.expectEqualStrings("second", loaded.title);
    try testing.expectEqualStrings("text", loaded.body);
    try testing.expectEqual(2, loaded.tags.len);
    try testing.expectEqualStrings("a", loaded.tags[0]);
    try testing.expectEqualStrings("b", loaded.tags[1]);

    const empty = (try get(conn, arena.allocator(), 1)).?;
    try testing.expectEqual(0, empty.tags.len);

    try testing.expectEqual(null, try get(conn, arena.allocator(), 3));
}

test "ids are not reused after the newest note is deleted" {
    const conn = try openTestDb();
    defer conn.close();

    _ = try create(conn, .{ .title = "a" });
    const b = try create(conn, .{ .title = "b", .tags = &.{"t"} });
    try conn.exec("DELETE FROM notes WHERE id = ?", .{b.id});
    const c = try create(conn, .{ .title = "c" });
    try testing.expectEqual(3, c.id);

    // Tags of the deleted note went with it.
    var stmt = try conn.prepare("SELECT count(*) FROM note_tags");
    defer stmt.finalize();
    _ = try stmt.step();
    try testing.expectEqual(0, stmt.columnInt(0));
}
