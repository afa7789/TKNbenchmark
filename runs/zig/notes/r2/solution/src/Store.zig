//! Persistent note storage in a SQLite database.
//!
//! A single connection is shared by all requests and serialized with a mutex;
//! SQLite is in-process and fast enough that this is not a bottleneck here.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const c = @import("c");

const sqlite = @import("sqlite.zig");
const note = @import("note.zig");
const Note = note.Note;

const Store = @This();

db: sqlite.Db,
mutex: Io.Mutex = .init,
io: Io,

pub const Error = sqlite.Error || Allocator.Error;

const schema =
    \\PRAGMA journal_mode = WAL;
    \\PRAGMA synchronous = NORMAL;
    \\PRAGMA foreign_keys = ON;
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
    const db: sqlite.Db = try .open(path);
    errdefer db.close();
    db.setBusyTimeout(5000);
    try db.exec(schema);
    try db.createScalarFunction("contains_ci", 2, containsIgnoreCase);
    return .{ .db = db, .io = io };
}

pub fn close(store: *Store) void {
    store.db.close();
    store.* = undefined;
}

pub const Filter = struct {
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
    /// Sorted by tag ascending.
    tags: []const TagCount,
};

pub fn create(store: *Store, arena: Allocator, input: note.Input) Error!Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    try store.db.exec("BEGIN IMMEDIATE");
    errdefer store.rollback();

    const insert = try store.db.prepare("INSERT INTO notes (title, body) VALUES (?, ?)");
    defer insert.deinit();
    try insert.bindAll(.{ input.title, input.body });
    try insert.run();
    const id = store.db.lastInsertRowId();

    try store.insertTags(id, input.tags);
    try store.db.exec("COMMIT");
    return try copyNote(arena, id, input);
}

/// Returns null if no note has this id.
pub fn get(store: *Store, arena: Allocator, id: i64) Error!?Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    const select = try store.db.prepare("SELECT id, title, body FROM notes WHERE id = ?");
    defer select.deinit();
    try select.bind(1, id);
    if (!try select.step()) return null;

    const tags_stmt = try store.prepareTagsQuery();
    defer tags_stmt.deinit();
    return try readNote(arena, select, tags_stmt);
}

/// Replaces a note's title, body and tags. Returns null if no note has this id.
pub fn update(store: *Store, arena: Allocator, id: i64, input: note.Input) Error!?Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    try store.db.exec("BEGIN IMMEDIATE");
    errdefer store.rollback();

    const stmt = try store.db.prepare("UPDATE notes SET title = ?, body = ? WHERE id = ?");
    defer stmt.deinit();
    try stmt.bindAll(.{ input.title, input.body, id });
    try stmt.run();
    if (store.db.changes() == 0) {
        store.rollback();
        return null;
    }

    try store.deleteTags(id);
    try store.insertTags(id, input.tags);
    try store.db.exec("COMMIT");
    return try copyNote(arena, id, input);
}

/// Returns false if no note has this id.
pub fn delete(store: *Store, id: i64) Error!bool {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    try store.db.exec("BEGIN IMMEDIATE");
    errdefer store.rollback();

    try store.deleteTags(id);
    const stmt = try store.db.prepare("DELETE FROM notes WHERE id = ?");
    defer stmt.deinit();
    try stmt.bind(1, id);
    try stmt.run();
    const deleted = store.db.changes() > 0;
    try store.db.exec("COMMIT");
    return deleted;
}

/// Returns the notes matching `filter`, ordered by id ascending.
pub fn list(store: *Store, arena: Allocator, filter: Filter) Error![]Note {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    const select = try store.db.prepare(
        \\SELECT id, title, body FROM notes AS n
        \\WHERE id > ?1
        \\  AND (?2 IS NULL OR EXISTS (SELECT 1 FROM note_tags AS t WHERE t.note_id = n.id AND t.tag = ?2))
        \\  AND (?3 IS NULL OR contains_ci(title, ?3) OR contains_ci(body, ?3))
        \\ORDER BY id
        \\LIMIT ?4
    );
    defer select.deinit();
    try select.bindAll(.{ filter.after, filter.tag, filter.query, filter.limit });

    const tags_stmt = try store.prepareTagsQuery();
    defer tags_stmt.deinit();

    var notes: std.ArrayList(Note) = .empty;
    while (try select.step()) try notes.append(arena, try readNote(arena, select, tags_stmt));
    return notes.items;
}

pub fn stats(store: *Store, arena: Allocator) Error!Stats {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    const count = try store.db.prepare("SELECT count(*) FROM notes");
    defer count.deinit();
    _ = try count.step();
    const notes = count.columnInt(0);

    const tags = try store.tagCounts(arena, "SELECT tag, count(*) FROM note_tags GROUP BY tag ORDER BY tag");
    return .{ .notes = notes, .tags = tags };
}

/// Returns every tag in use, ordered by count descending, then tag ascending.
pub fn tagsByCount(store: *Store, arena: Allocator) Error![]TagCount {
    store.mutex.lockUncancelable(store.io);
    defer store.mutex.unlock(store.io);

    return store.tagCounts(arena,
        \\SELECT tag, count(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag ASC
    );
}

fn tagCounts(store: *Store, arena: Allocator, sql: []const u8) Error![]TagCount {
    const stmt = try store.db.prepare(sql);
    defer stmt.deinit();
    var result: std.ArrayList(TagCount) = .empty;
    while (try stmt.step()) {
        try result.append(arena, .{
            .tag = try arena.dupe(u8, stmt.columnText(0)),
            .count = stmt.columnInt(1),
        });
    }
    return result.items;
}

fn insertTags(store: *Store, id: i64, tags: []const []const u8) Error!void {
    if (tags.len == 0) return;
    const stmt = try store.db.prepare("INSERT OR IGNORE INTO note_tags (note_id, tag) VALUES (?, ?)");
    defer stmt.deinit();
    for (tags) |tag| {
        stmt.reset();
        try stmt.bindAll(.{ id, tag });
        try stmt.run();
    }
}

fn deleteTags(store: *Store, id: i64) Error!void {
    const stmt = try store.db.prepare("DELETE FROM note_tags WHERE note_id = ?");
    defer stmt.deinit();
    try stmt.bind(1, id);
    try stmt.run();
}

fn prepareTagsQuery(store: *Store) Error!sqlite.Statement {
    return store.db.prepare("SELECT tag FROM note_tags WHERE note_id = ? ORDER BY tag");
}

fn rollback(store: *Store) void {
    store.db.exec("ROLLBACK") catch {};
}

/// Reads a note from the current row of `row`, whose columns are id, title, body.
fn readNote(arena: Allocator, row: sqlite.Statement, tags_stmt: sqlite.Statement) Error!Note {
    const id = row.columnInt(0);
    const title = try arena.dupe(u8, row.columnText(1));
    const body = try arena.dupe(u8, row.columnText(2));

    tags_stmt.reset();
    try tags_stmt.bind(1, id);
    var tags: std.ArrayList([]const u8) = .empty;
    while (try tags_stmt.step()) try tags.append(arena, try arena.dupe(u8, tags_stmt.columnText(0)));

    return .{ .id = id, .title = title, .body = body, .tags = tags.items };
}

fn copyNote(arena: Allocator, id: i64, input: note.Input) Allocator.Error!Note {
    const tags = try arena.alloc([]const u8, input.tags.len);
    for (tags, input.tags) |*dst, src| dst.* = try arena.dupe(u8, src);
    return .{
        .id = id,
        .title = try arena.dupe(u8, input.title),
        .body = try arena.dupe(u8, input.body),
        .tags = tags,
    };
}

/// SQL function `contains_ci(haystack, needle)`: true if `needle` occurs in
/// `haystack`, ignoring ASCII case.
fn containsIgnoreCase(ctx: ?*c.sqlite3_context, argc: c_int, argv: [*c]?*c.sqlite3_value) callconv(.c) void {
    std.debug.assert(argc == 2);
    const haystack = sqlite.valueText(argv[0]) orelse return sqlite.resultNull(ctx);
    const needle = sqlite.valueText(argv[1]) orelse return sqlite.resultNull(ctx);
    sqlite.resultBool(ctx, std.ascii.indexOfIgnoreCase(haystack, needle) != null);
}

const testing = std.testing;

fn testInput(title: []const u8, body: []const u8, tags: []const []const u8) note.Input {
    return .{ .title = title, .body = body, .tags = tags };
}

test "create, get, update, delete" {
    var store: Store = try .open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const first = try store.create(a, testInput("one", "", &.{ "a", "b" }));
    try testing.expectEqual(1, first.id);
    const second = try store.create(a, testInput("two", "body", &.{}));
    try testing.expectEqual(2, second.id);

    const got = (try store.get(a, 1)).?;
    try testing.expectEqualStrings("one", got.title);
    try testing.expectEqual(2, got.tags.len);
    try testing.expectEqual(null, try store.get(a, 3));

    const updated = (try store.update(a, 1, testInput("uno", "x", &.{"c"}))).?;
    try testing.expectEqualStrings("uno", updated.title);
    try testing.expectEqual(null, try store.update(a, 9, testInput("x", "", &.{})));
    const reread = (try store.get(a, 1)).?;
    try testing.expectEqual(1, reread.tags.len);
    try testing.expectEqualStrings("c", reread.tags[0]);

    try testing.expect(try store.delete(2));
    try testing.expect(!try store.delete(2));
    const third = try store.create(a, testInput("three", "", &.{}));
    try testing.expectEqual(3, third.id);
}

test "list filters and tag counts" {
    var store: Store = try .open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try store.create(a, testInput("Hello world", "", &.{"greet"}));
    _ = try store.create(a, testInput("other", "say HELLO 100%", &.{ "greet", "misc" }));
    _ = try store.create(a, testInput("nothing", "", &.{}));

    try testing.expectEqual(3, (try store.list(a, .{})).len);
    try testing.expectEqual(2, (try store.list(a, .{ .query = "hello" })).len);
    try testing.expectEqual(1, (try store.list(a, .{ .query = "0%" })).len);
    try testing.expectEqual(0, (try store.list(a, .{ .query = "_" })).len);
    const misc = try store.list(a, .{ .tag = "misc", .query = "hello" });
    try testing.expectEqual(1, misc.len);
    try testing.expectEqual(2, misc[0].id);
    try testing.expectEqual(2, misc[0].tags.len);
    const paged = try store.list(a, .{ .after = 1, .limit = 1 });
    try testing.expectEqual(1, paged.len);
    try testing.expectEqual(2, paged[0].id);

    const s = try store.stats(a);
    try testing.expectEqual(3, s.notes);
    try testing.expectEqual(2, s.tags.len);
    try testing.expectEqualStrings("greet", s.tags[0].tag);
    try testing.expectEqual(2, s.tags[0].count);

    _ = try store.delete(2);
    const by_count = try store.tagsByCount(a);
    try testing.expectEqual(1, by_count.len);
    try testing.expectEqualStrings("greet", by_count[0].tag);
    try testing.expectEqual(1, by_count[0].count);
}
