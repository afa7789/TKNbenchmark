//! Persistent note storage on a single SQLite connection.
//!
//! All operations serialize on one mutex: SQLite allows only one writer at a
//! time anyway, and a single connection keeps transactions simple.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const sqlite = @import("sqlite.zig");
const Note = @import("note.zig").Note;
const Input = @import("note.zig").Input;

const Store = @This();

db: sqlite.Db,
mutex: Io.Mutex = .init,
io: Io,

pub const Error = sqlite.Error || Allocator.Error;

const schema =
    \\PRAGMA journal_mode = WAL;
    \\PRAGMA synchronous = NORMAL;
    \\PRAGMA foreign_keys = ON;
    \\PRAGMA busy_timeout = 5000;
    \\CREATE TABLE IF NOT EXISTS notes (
    \\    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    title TEXT NOT NULL,
    \\    body  TEXT NOT NULL
    \\);
    \\CREATE TABLE IF NOT EXISTS note_tags (
    \\    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    \\    tag     TEXT NOT NULL,
    \\    PRIMARY KEY (note_id, tag)
    \\) WITHOUT ROWID;
    \\CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags(tag, note_id);
;

pub fn open(io: Io, path: [:0]const u8) sqlite.Error!Store {
    const db = try sqlite.Db.open(path);
    errdefer db.close();
    try db.exec(schema);
    return .{ .db = db, .io = io };
}

pub fn close(s: *Store) void {
    s.db.close();
}

fn lock(s: *Store) void {
    s.mutex.lockUncancelable(s.io);
}

fn unlock(s: *Store) void {
    s.mutex.unlock(s.io);
}

/// Runs `body` inside a write transaction, rolling back if it fails.
fn transaction(s: *Store, comptime T: type, body: anytype, args: anytype) Error!T {
    try s.db.exec("BEGIN IMMEDIATE");
    const result = @call(.auto, body, args) catch |err| {
        s.db.exec("ROLLBACK") catch {};
        return err;
    };
    try s.db.exec("COMMIT");
    return result;
}

pub fn create(s: *Store, gpa: Allocator, input: Input) Error!Note {
    s.lock();
    defer s.unlock();
    const id = try s.transaction(i64, createTx, .{ s, input });
    return .{ .id = id, .title = try gpa.dupe(u8, input.title), .body = try gpa.dupe(u8, input.body), .tags = try dupeTags(gpa, input.tags) };
}

fn createTx(s: *Store, input: Input) Error!i64 {
    const stmt = try s.db.prepare("INSERT INTO notes (title, body) VALUES (?, ?)");
    defer stmt.finalize();
    try stmt.bindAll(.{ input.title, input.body });
    _ = try stmt.step();
    const id = s.db.lastInsertRowId();
    try s.insertTags(id, input.tags);
    return id;
}

/// Replaces the note's content; returns null when the note does not exist.
pub fn update(s: *Store, gpa: Allocator, id: i64, input: Input) Error!?Note {
    s.lock();
    defer s.unlock();
    if (!try s.transaction(bool, updateTx, .{ s, id, input })) return null;
    return .{ .id = id, .title = try gpa.dupe(u8, input.title), .body = try gpa.dupe(u8, input.body), .tags = try dupeTags(gpa, input.tags) };
}

fn updateTx(s: *Store, id: i64, input: Input) Error!bool {
    {
        const stmt = try s.db.prepare("UPDATE notes SET title = ?, body = ? WHERE id = ?");
        defer stmt.finalize();
        try stmt.bindAll(.{ input.title, input.body, id });
        _ = try stmt.step();
        if (s.db.changes() == 0) return false;
    }
    {
        const stmt = try s.db.prepare("DELETE FROM note_tags WHERE note_id = ?");
        defer stmt.finalize();
        try stmt.bind(1, id);
        _ = try stmt.step();
    }
    try s.insertTags(id, input.tags);
    return true;
}

fn insertTags(s: *Store, id: i64, tags: []const []const u8) Error!void {
    if (tags.len == 0) return;
    const stmt = try s.db.prepare("INSERT OR IGNORE INTO note_tags (note_id, tag) VALUES (?, ?)");
    defer stmt.finalize();
    for (tags) |tag| {
        try stmt.reset();
        try stmt.bindAll(.{ id, tag });
        _ = try stmt.step();
    }
}

/// Deletes a note; returns false when it does not exist.
pub fn delete(s: *Store, id: i64) Error!bool {
    s.lock();
    defer s.unlock();
    const stmt = try s.db.prepare("DELETE FROM notes WHERE id = ?");
    defer stmt.finalize();
    try stmt.bind(1, id);
    _ = try stmt.step();
    return s.db.changes() > 0;
}

pub fn get(s: *Store, gpa: Allocator, id: i64) Error!?Note {
    s.lock();
    defer s.unlock();
    const stmt = try s.db.prepare("SELECT id, title, body FROM notes WHERE id = ?");
    defer stmt.finalize();
    try stmt.bind(1, id);
    if (!try stmt.step()) return null;

    const tags_stmt = try s.prepareTags();
    defer tags_stmt.finalize();
    return try readNote(gpa, stmt, tags_stmt);
}

pub const Filter = struct {
    tag: ?[]const u8 = null,
    /// Case-insensitive (ASCII) substring of title or body.
    query: ?[]const u8 = null,
    after: i64 = 0,
    limit: usize = 100,
};

/// Notes matching `filter`, ordered by id ascending.
pub fn list(s: *Store, gpa: Allocator, filter: Filter) Error![]Note {
    s.lock();
    defer s.unlock();

    const stmt = if (filter.tag) |tag| blk: {
        const st = try s.db.prepare(
            \\SELECT n.id, n.title, n.body FROM notes n
            \\JOIN note_tags t ON t.note_id = n.id
            \\WHERE t.tag = ? AND n.id > ? ORDER BY n.id
        );
        errdefer st.finalize();
        try st.bindAll(.{ tag, filter.after });
        break :blk st;
    } else blk: {
        const st = try s.db.prepare("SELECT id, title, body FROM notes WHERE id > ? ORDER BY id");
        errdefer st.finalize();
        try st.bind(1, filter.after);
        break :blk st;
    };
    defer stmt.finalize();

    const tags_stmt = try s.prepareTags();
    defer tags_stmt.finalize();

    var notes: std.ArrayList(Note) = .empty;
    errdefer notes.deinit(gpa);
    while (notes.items.len < filter.limit and try stmt.step()) {
        if (filter.query) |q| {
            if (!containsIgnoreCase(stmt.text(1), q) and !containsIgnoreCase(stmt.text(2), q)) continue;
        }
        try notes.append(gpa, try readNote(gpa, stmt, tags_stmt));
    }
    return notes.toOwnedSlice(gpa);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

fn prepareTags(s: *Store) Error!sqlite.Stmt {
    return s.db.prepare("SELECT tag FROM note_tags WHERE note_id = ? ORDER BY tag");
}

/// Copies the current row of `stmt` (id, title, body) plus its tags into `gpa` memory.
fn readNote(gpa: Allocator, stmt: sqlite.Stmt, tags_stmt: sqlite.Stmt) Error!Note {
    const id = stmt.int(0);
    try tags_stmt.reset();
    try tags_stmt.bind(1, id);
    var tags: std.ArrayList([]const u8) = .empty;
    while (try tags_stmt.step()) try tags.append(gpa, try gpa.dupe(u8, tags_stmt.text(0)));
    return .{
        .id = id,
        .title = try gpa.dupe(u8, stmt.text(1)),
        .body = try gpa.dupe(u8, stmt.text(2)),
        .tags = try tags.toOwnedSlice(gpa),
    };
}

fn dupeTags(gpa: Allocator, tags: []const []const u8) Allocator.Error![]const []const u8 {
    const out = try gpa.alloc([]const u8, tags.len);
    for (tags, out) |tag, *slot| slot.* = try gpa.dupe(u8, tag);
    return out;
}

pub const TagCount = struct {
    tag: []const u8,
    count: i64,
};

/// Tags with the number of notes carrying them, by count descending then tag ascending.
pub fn tagCounts(s: *Store, gpa: Allocator) Error![]TagCount {
    s.lock();
    defer s.unlock();
    const stmt = try s.db.prepare(
        \\SELECT tag, COUNT(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag ASC
    );
    defer stmt.finalize();
    var out: std.ArrayList(TagCount) = .empty;
    errdefer out.deinit(gpa);
    while (try stmt.step()) {
        try out.append(gpa, .{ .tag = try gpa.dupe(u8, stmt.text(0)), .count = stmt.int(1) });
    }
    return out.toOwnedSlice(gpa);
}

pub fn noteCount(s: *Store) Error!i64 {
    s.lock();
    defer s.unlock();
    const stmt = try s.db.prepare("SELECT COUNT(*) FROM notes");
    defer stmt.finalize();
    _ = try stmt.step();
    return stmt.int(0);
}

const testing = std.testing;

test "create, update, delete, list and count" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var store = try Store.open(testing.io, ":memory:");
    defer store.close();

    const n1 = try store.create(a, .{ .title = "Hello", .body = "", .tags = &.{ "greet", "x" } });
    const n2 = try store.create(a, .{ .title = "other", .body = "say HELLO", .tags = &.{"x"} });
    _ = try store.create(a, .{ .title = "nothing", .body = "", .tags = &.{} });
    try testing.expectEqual(1, n1.id);
    try testing.expectEqual(2, n2.id);

    try testing.expectEqual(2, (try store.list(a, .{ .query = "hello" })).len);
    try testing.expectEqual(1, (try store.list(a, .{ .tag = "greet" })).len);
    try testing.expectEqual(1, (try store.list(a, .{ .after = 2 })).len);
    try testing.expectEqual(1, (try store.list(a, .{ .limit = 1 })).len);

    const counts = try store.tagCounts(a);
    try testing.expectEqual(2, counts.len);
    try testing.expectEqualStrings("x", counts[0].tag);
    try testing.expectEqual(2, counts[0].count);

    try testing.expect(try store.delete(1));
    try testing.expect(!try store.delete(1));
    try testing.expectEqual(null, try store.get(a, 1));
    try testing.expectEqual(null, try store.update(a, 1, .{ .title = "t", .body = "", .tags = &.{} }));

    const n4 = try store.create(a, .{ .title = "again", .body = "", .tags = &.{} });
    try testing.expectEqual(4, n4.id);
    try testing.expectEqual(3, try store.noteCount());
    try testing.expectEqual(1, (try store.tagCounts(a)).len);

    const upd = (try store.update(a, 2, .{ .title = "new", .body = "b", .tags = &.{"y"} })).?;
    try testing.expectEqualStrings("new", upd.title);
    const got = (try store.get(a, 2)).?;
    try testing.expectEqualStrings("y", got.tags[0]);
}
