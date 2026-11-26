//! Data access for `PUT /notes/{id}` and `DELETE /notes/{id}`.
//!
//! Owner: branch `crud`. Lock the store with `Store.acquire`/`release` and use
//! `sqlite.Db.transaction` for multi-statement writes; reuse the helpers of
//! `store/notes.zig` (`fetch`, `insertTags`, …). Deleting a note deletes its
//! tags (`ON DELETE CASCADE`).

const std = @import("std");
const Store = @import("../Store.zig");
const sqlite = @import("../sqlite.zig");
const model = @import("../model.zig");
const notes = @import("notes.zig");
const Note = model.Note;
const NoteInput = model.NoteInput;

/// Replaces the title, body and tags of note `id` with `input` and returns
/// the updated note, or null if there is no such note. The note refers to the
/// memory of `input`.
pub fn update(store: *Store, id: i64, input: NoteInput) !?Note {
    const db = try store.acquire();
    defer store.release();
    if (!try db.transaction(replaceNote, .{ id, input })) return null;
    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

/// Deletes note `id` and its tags. Returns false if there was no such note.
pub fn remove(store: *Store, id: i64) !bool {
    const db = try store.acquire();
    defer store.release();
    // A single statement: its tags go with it through `ON DELETE CASCADE`.
    try db.run("DELETE FROM notes WHERE id = ?1", .{id});
    return db.changes() > 0;
}

fn replaceNote(db: sqlite.Db, id: i64, input: NoteInput) !bool {
    try db.run("UPDATE notes SET title = ?2, body = ?3 WHERE id = ?1", .{ id, input.title, input.body });
    if (db.changes() == 0) return false;
    try db.run("DELETE FROM note_tags WHERE note_id = ?1", .{id});
    try notes.insertTags(db, id, input.tags);
    return true;
}

const testing = std.testing;

test "update replaces every field and keeps the id" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const created = try notes.create(&store, .{ .title = "old", .body = "text", .tags = &.{ "x", "y" } });
    const updated = (try update(&store, created.id, .{ .title = "new", .tags = &.{ "a", "y" } })).?;
    try testing.expectEqualDeep(Note{ .id = created.id, .title = "new", .body = "", .tags = &.{ "a", "y" } }, updated);
    try testing.expectEqualDeep(updated, (try notes.get(&store, a, created.id)).?);

    // Replacing with identical values still finds the note.
    try testing.expect(try update(&store, created.id, .{ .title = "new", .tags = &.{ "a", "y" } }) != null);
    try testing.expectEqual(null, try update(&store, created.id + 1, .{ .title = "none" }));
}

test "remove deletes the note and its tags, and ids are not reused" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try notes.create(&store, .{ .title = "a" });
    const second = try notes.create(&store, .{ .title = "b", .tags = &.{"t"} });
    try testing.expect(try remove(&store, second.id));
    try testing.expectEqual(null, try notes.get(&store, a, second.id));
    try testing.expect(!try remove(&store, second.id));

    const stmt = try store.db.prepare("SELECT count(*) FROM note_tags");
    defer stmt.finalize();
    try testing.expect(try stmt.step());
    try testing.expectEqual(@as(i64, 0), stmt.int(0));

    const third = try notes.create(&store, .{ .title = "c" });
    try testing.expectEqual(second.id + 1, third.id);
}
