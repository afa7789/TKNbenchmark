//! Persistent notes storage on top of SQLite.
//!
//! A single connection is shared by all request handlers and guarded by a
//! mutex, which keeps every operation (including multi-statement writes)
//! atomic with respect to the others.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const sqlite = @import("sqlite.zig");

const Store = @This();

io: Io,
db: sqlite.Db,
mutex: Io.Mutex = .init,

pub const Error = sqlite.Error || Allocator.Error;

pub const Note = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    tags: []const []const u8,
};

/// Validated content of a note; `tags` must be sorted and free of duplicates.
pub const NoteInput = struct {
    title: []const u8,
    body: []const u8,
    tags: []const []const u8,
};

pub const ListFilter = struct {
    tag: ?[]const u8 = null,
    query: ?[]const u8 = null,
    after: i64 = 0,
    limit: u32 = 100,
};

pub const TagCount = struct {
    tag: []const u8,
    count: i64,
};

pub const Stats = struct {
    notes: i64,
    /// Ordered by count descending, then tag ascending.
    tags: []const TagCount,
};

const schema =
    \\CREATE TABLE IF NOT EXISTS notes (
    \\    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    title TEXT NOT NULL,
    \\    body  TEXT NOT NULL
    \\);
    \\CREATE TABLE IF NOT EXISTS note_tags (
    \\    note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
    \\    tag     TEXT NOT NULL,
    \\    PRIMARY KEY (note_id, tag)
    \\) WITHOUT ROWID;
    \\CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags (tag, note_id);
;

pub fn open(io: Io, path: [:0]const u8) sqlite.Error!Store {
    const db = try sqlite.Db.open(path);
    errdefer db.close();
    try db.exec("PRAGMA busy_timeout = 5000");
    // The schema is created before switching to WAL so that the main database
    // file is fully initialized on disk right away.
    try db.exec(schema);
    try db.exec("PRAGMA journal_mode = WAL");
    try db.exec("PRAGMA synchronous = NORMAL");
    try db.exec("PRAGMA foreign_keys = ON");
    return .{ .io = io, .db = db };
}

pub fn close(store: *Store) void {
    store.db.close();
    store.* = undefined;
}

/// Stores a new note. The returned note refers to the memory of `input`.
pub fn create(store: *Store, input: NoteInput) Error!Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    try store.db.exec("BEGIN IMMEDIATE");
    errdefer store.rollback();

    const ins = try store.db.prepare("INSERT INTO notes (title, body) VALUES (?1, ?2)");
    defer ins.finalize();
    try ins.bindAll(.{ input.title, input.body });
    try ins.run();
    const id = store.db.lastInsertRowId();

    try store.insertTags(id, input.tags);
    try store.db.exec("COMMIT");
    return noteFromInput(id, input);
}

pub fn get(store: *Store, arena: Allocator, id: i64) Error!?Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    const sel = try store.db.prepare("SELECT title, body FROM notes WHERE id = ?1");
    defer sel.finalize();
    try sel.bind(1, id);
    if (!try sel.step()) return null;

    const tags_stmt = try store.prepareTagsQuery();
    defer tags_stmt.finalize();
    return .{
        .id = id,
        .title = try arena.dupe(u8, sel.columnText(0)),
        .body = try arena.dupe(u8, sel.columnText(1)),
        .tags = try readTags(arena, tags_stmt, id),
    };
}

/// Replaces a note's content; returns null if the note does not exist.
/// The returned note refers to the memory of `input`.
pub fn update(store: *Store, id: i64, input: NoteInput) Error!?Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    try store.db.exec("BEGIN IMMEDIATE");
    errdefer store.rollback();

    const upd = try store.db.prepare("UPDATE notes SET title = ?1, body = ?2 WHERE id = ?3");
    defer upd.finalize();
    try upd.bindAll(.{ input.title, input.body, id });
    try upd.run();
    if (store.db.changes() == 0) {
        store.rollback();
        return null;
    }

    const del = try store.db.prepare("DELETE FROM note_tags WHERE note_id = ?1");
    defer del.finalize();
    try del.bind(1, id);
    try del.run();

    try store.insertTags(id, input.tags);
    try store.db.exec("COMMIT");
    return noteFromInput(id, input);
}

/// Deletes a note; returns false if it does not exist.
pub fn delete(store: *Store, id: i64) Error!bool {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    try store.db.exec("BEGIN IMMEDIATE");
    errdefer store.rollback();

    const del_tags = try store.db.prepare("DELETE FROM note_tags WHERE note_id = ?1");
    defer del_tags.finalize();
    try del_tags.bind(1, id);
    try del_tags.run();

    const del = try store.db.prepare("DELETE FROM notes WHERE id = ?1");
    defer del.finalize();
    try del.bind(1, id);
    try del.run();
    const found = store.db.changes() > 0;

    try store.db.exec("COMMIT");
    return found;
}

pub fn list(store: *Store, arena: Allocator, filter: ListFilter) Error![]Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    // SQLite's built-in lower() folds ASCII letters only, which is exactly the
    // case-insensitivity the API promises.
    const sel = try store.db.prepare(
        \\SELECT id, title, body FROM notes
        \\WHERE id > ?1
        \\  AND (?2 IS NULL OR EXISTS (
        \\        SELECT 1 FROM note_tags WHERE note_id = notes.id AND tag = ?2))
        \\  AND (?3 IS NULL OR instr(lower(title), lower(?3)) > 0
        \\                  OR instr(lower(body), lower(?3)) > 0)
        \\ORDER BY id
        \\LIMIT ?4
    );
    defer sel.finalize();
    try sel.bindAll(.{ filter.after, filter.tag, filter.query, filter.limit });

    const tags_stmt = try store.prepareTagsQuery();
    defer tags_stmt.finalize();

    var notes: std.ArrayList(Note) = .empty;
    while (try sel.step()) {
        const id = sel.columnInt(0);
        try notes.append(arena, .{
            .id = id,
            .title = try arena.dupe(u8, sel.columnText(1)),
            .body = try arena.dupe(u8, sel.columnText(2)),
            .tags = try readTags(arena, tags_stmt, id),
        });
    }
    return notes.items;
}

pub fn stats(store: *Store, arena: Allocator) Error!Stats {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    const count = try store.db.prepare("SELECT count(*) FROM notes");
    defer count.finalize();
    _ = try count.step();
    const notes = count.columnInt(0);

    const sel = try store.db.prepare(
        \\SELECT tag, count(*) AS n FROM note_tags
        \\GROUP BY tag
        \\ORDER BY n DESC, tag ASC
    );
    defer sel.finalize();

    var tags: std.ArrayList(TagCount) = .empty;
    while (try sel.step()) {
        try tags.append(arena, .{
            .tag = try arena.dupe(u8, sel.columnText(0)),
            .count = sel.columnInt(1),
        });
    }
    return .{ .notes = notes, .tags = tags.items };
}

fn insertTags(store: *Store, id: i64, tags: []const []const u8) sqlite.Error!void {
    if (tags.len == 0) return;
    const ins = try store.db.prepare("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)");
    defer ins.finalize();
    for (tags) |tag| {
        try ins.bindAll(.{ id, tag });
        try ins.run();
        ins.reset();
    }
}

fn prepareTagsQuery(store: *Store) sqlite.Error!sqlite.Statement {
    return store.db.prepare("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag");
}

fn readTags(arena: Allocator, stmt: sqlite.Statement, id: i64) Error![]const []const u8 {
    defer stmt.reset();
    try stmt.bind(1, id);
    var tags: std.ArrayList([]const u8) = .empty;
    while (try stmt.step()) {
        try tags.append(arena, try arena.dupe(u8, stmt.columnText(0)));
    }
    return tags.items;
}

fn rollback(store: *Store) void {
    store.db.exec("ROLLBACK") catch {};
}

fn noteFromInput(id: i64, input: NoteInput) Note {
    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

const testing = std.testing;

test "create, get, update, delete and list" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const a = try store.create(.{ .title = "Hello", .body = "World", .tags = &.{ "a", "b" } });
    const b = try store.create(.{ .title = "other", .body = "", .tags = &.{"b"} });
    try testing.expectEqual(@as(i64, 1), a.id);
    try testing.expectEqual(@as(i64, 2), b.id);

    const got = (try store.get(arena, 1)).?;
    try testing.expectEqualStrings("Hello", got.title);
    try testing.expectEqual(@as(usize, 2), got.tags.len);
    try testing.expectEqualStrings("b", got.tags[1]);

    try testing.expectEqual(@as(usize, 1), (try store.list(arena, .{ .query = "WORLD" })).len);
    try testing.expectEqual(@as(usize, 2), (try store.list(arena, .{ .tag = "b" })).len);
    try testing.expectEqual(@as(usize, 1), (try store.list(arena, .{ .after = 1 })).len);
    try testing.expectEqual(@as(usize, 1), (try store.list(arena, .{ .limit = 1 })).len);

    const s = try store.stats(arena);
    try testing.expectEqual(@as(i64, 2), s.notes);
    try testing.expectEqualStrings("b", s.tags[0].tag);
    try testing.expectEqual(@as(i64, 2), s.tags[0].count);

    try testing.expect((try store.update(1, .{ .title = "x", .body = "", .tags = &.{} })) != null);
    try testing.expect((try store.update(9, .{ .title = "x", .body = "", .tags = &.{} })) == null);
    try testing.expect(try store.delete(2));
    try testing.expect(!try store.delete(2));
    try testing.expectEqual(@as(usize, 0), (try store.stats(arena)).tags.len);

    // Ids are never reused.
    const c = try store.create(.{ .title = "c", .body = "", .tags = &.{} });
    try testing.expectEqual(@as(i64, 3), c.id);
}
