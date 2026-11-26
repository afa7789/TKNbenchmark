//! Data access for single notes: create and read, plus the building blocks
//! other data-access modules (`crud.zig`, `list.zig`, `stats.zig`) reuse.
//!
//! Public functions taking a `*Store` lock it themselves; those taking a
//! `sqlite.Db` expect the caller to hold the lock (see `Store.acquire`).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Store = @import("../Store.zig");
const sqlite = @import("../sqlite.zig");
const model = @import("../model.zig");
const Note = model.Note;
const NoteInput = model.NoteInput;

/// Columns `scanNote` expects, in order, for a query on `notes`.
pub const note_columns = "notes.id, notes.title, notes.body";

/// Inserts a note and returns it with its new id. The note refers to the
/// memory of `input`.
pub fn create(store: *Store, input: NoteInput) !Note {
    const db = try store.acquire();
    defer store.release();
    const id = try db.transaction(insertNote, .{input});
    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

/// The note with `id`, or null if there is none.
pub fn get(store: *Store, arena: Allocator, id: i64) !?Note {
    const db = try store.acquire();
    defer store.release();
    return fetch(db, arena, id);
}

/// The note with `id`, tags included, or null if there is none.
pub fn fetch(db: sqlite.Db, arena: Allocator, id: i64) !?Note {
    const stmt = try db.prepare("SELECT " ++ note_columns ++ " FROM notes WHERE id = ?1");
    defer stmt.finalize();
    try stmt.bindAll(.{id});
    if (!try stmt.step()) return null;
    var note = try scanNote(stmt, arena);
    note.tags = try loadTags(db, arena, id);
    return note;
}

/// Reads the `note_columns` of the current row. `tags` is left empty.
pub fn scanNote(stmt: sqlite.Statement, arena: Allocator) !Note {
    return .{
        .id = stmt.int(0),
        .title = try stmt.textAlloc(arena, 1),
        .body = try stmt.textAlloc(arena, 2),
        .tags = &.{},
    };
}

/// The tags of note `id`, sorted ascending.
pub fn loadTags(db: sqlite.Db, arena: Allocator, id: i64) ![]const []const u8 {
    const stmt = try db.prepare("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag");
    defer stmt.finalize();
    try stmt.bindAll(.{id});
    var tags: std.ArrayList([]const u8) = .empty;
    while (try stmt.step()) try tags.append(arena, try stmt.textAlloc(arena, 0));
    return tags.toOwnedSlice(arena);
}

/// Adds `tags` (already validated and deduplicated) to note `id`.
pub fn insertTags(db: sqlite.Db, id: i64, tags: []const []const u8) !void {
    if (tags.len == 0) return;
    const stmt = try db.prepare("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)");
    defer stmt.finalize();
    for (tags) |tag| {
        stmt.reset();
        try stmt.bindAll(.{ id, tag });
        while (try stmt.step()) {}
    }
}

fn insertNote(db: sqlite.Db, input: NoteInput) !i64 {
    try db.run("INSERT INTO notes (title, body) VALUES (?1, ?2)", .{ input.title, input.body });
    const id = db.lastInsertRowId();
    try insertTags(db, id, input.tags);
    return id;
}

const testing = std.testing;

test "create assigns increasing ids and get reads notes back" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const first = try create(&store, .{ .title = "first" });
    const second = try create(&store, .{ .title = "second", .body = "text", .tags = &.{ "a", "b" } });
    try testing.expectEqual(@as(i64, 1), first.id);
    try testing.expectEqual(@as(i64, 2), second.id);

    const got = (try get(&store, a, 2)).?;
    try testing.expectEqualDeep(second, got);
    try testing.expectEqual(null, try get(&store, a, 3));
}
