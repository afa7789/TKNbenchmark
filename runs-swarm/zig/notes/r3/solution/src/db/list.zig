//! Data access for listing notes with filters (GET /notes).

const std = @import("std");
const Allocator = std.mem.Allocator;
const sqlite = @import("sqlite.zig");
const Note = @import("../note.zig").Note;

pub const Error = sqlite.Error || Allocator.Error;

pub const max_limit = 100;

/// Which notes to list. All conditions are combined.
pub const Filter = struct {
    /// Only notes that have this tag.
    tag: ?[]const u8 = null,
    /// Only notes whose title or body contains this text, ignoring ASCII case.
    text: ?[]const u8 = null,
    /// Only notes with an id greater than this.
    after: i64 = 0,
    /// At most this many notes.
    limit: u32 = max_limit,
};

/// Tags are joined with this separator in the query result. It cannot
/// occur in a valid tag (see `note.isValidTag`).
const tag_separator = ',';

// `lower()` and `instr()` without ICU fold only ASCII letters, which is
// exactly the case-insensitivity required, and unlike LIKE there are no
// wildcard characters to escape. The tags come back with each row, sorted,
// so a whole page is read with a single statement.
const list_sql = std.fmt.comptimePrint(
    \\SELECT id, title, body,
    \\       (SELECT group_concat(tag, '{c}' ORDER BY tag) FROM note_tags WHERE note_id = notes.id)
    \\FROM notes
    \\WHERE id > ?1
    \\  AND (?2 IS NULL OR EXISTS (SELECT 1 FROM note_tags WHERE note_id = notes.id AND tag = ?2))
    \\  AND (?3 IS NULL OR instr(lower(title), lower(?3)) > 0 OR instr(lower(body), lower(?3)) > 0)
    \\ORDER BY id
    \\LIMIT ?4
, .{tag_separator});

/// The notes matching `filter`, ordered by id ascending.
pub fn list(db: sqlite.Db, arena: Allocator, filter: Filter) Error![]Note {
    var stmt = try db.prepare(list_sql);
    defer stmt.deinit();
    try stmt.bindAll(.{ filter.after, filter.tag, filter.text, filter.limit });

    var notes: std.ArrayList(Note) = .empty;
    while (try stmt.step()) {
        try notes.append(arena, .{
            .id = stmt.columnInt(0),
            .title = try stmt.columnTextAlloc(arena, 1),
            .body = try stmt.columnTextAlloc(arena, 2),
            .tags = try splitTags(arena, stmt.columnText(3)),
        });
    }
    return notes.toOwnedSlice(arena);
}

fn splitTags(arena: Allocator, joined: []const u8) Allocator.Error![]const []const u8 {
    if (joined.len == 0) return &.{};
    const owned = try arena.dupe(u8, joined);
    const tags = try arena.alloc([]const u8, std.mem.countScalar(u8, owned, tag_separator) + 1);
    var it = std.mem.splitScalar(u8, owned, tag_separator);
    for (tags) |*tag| tag.* = it.next().?;
    return tags;
}

const testing = std.testing;
const notes_db = @import("notes.zig");

fn openTestDb() !sqlite.Db {
    const db = try sqlite.Db.open(":memory:", .{});
    errdefer db.close();
    try db.exec("PRAGMA foreign_keys = ON");
    try @import("schema.zig").migrate(db);
    return db;
}

fn expectIds(want: []const i64, got: []const Note) !void {
    const ids = try testing.allocator.alloc(i64, got.len);
    defer testing.allocator.free(ids);
    for (got, ids) |n, *id| id.* = n.id;
    try testing.expectEqualSlices(i64, want, ids);
}

test "list returns every note with its tags in id order" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try expectIds(&.{}, try list(db, a, .{}));

    _ = try notes_db.insert(db, .{ .title = "a" });
    _ = try notes_db.insert(db, .{ .title = "b", .body = "x", .tags = &.{ "a-1", "t", "z" } });

    const all = try list(db, a, .{});
    try expectIds(&.{ 1, 2 }, all);
    try testing.expectEqualStrings("a", all[0].title);
    try testing.expectEqual(0, all[0].tags.len);
    try testing.expectEqualStrings("b", all[1].title);
    try testing.expectEqualStrings("x", all[1].body);
    try testing.expectEqual(3, all[1].tags.len);
    try testing.expectEqualStrings("a-1", all[1].tags[0]);
    try testing.expectEqualStrings("t", all[1].tags[1]);
    try testing.expectEqualStrings("z", all[1].tags[2]);
}

test "list filters by tag, text, after and limit" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try notes_db.insert(db, .{ .title = "Hello world", .tags = &.{"greet"} });
    _ = try notes_db.insert(db, .{ .title = "other", .body = "say HELLO", .tags = &.{ "greet", "misc" } });
    _ = try notes_db.insert(db, .{ .title = "100% _done_" });
    _ = try notes_db.insert(db, .{ .title = "Ünïcode", .body = "ÉTÉ" });

    try expectIds(&.{2}, try list(db, a, .{ .tag = "misc" }));
    try expectIds(&.{ 1, 2 }, try list(db, a, .{ .tag = "greet" }));
    try expectIds(&.{}, try list(db, a, .{ .tag = "gree" }));
    try expectIds(&.{ 1, 2 }, try list(db, a, .{ .text = "hello" }));
    try expectIds(&.{ 1, 2 }, try list(db, a, .{ .text = "HeLLo" }));
    try expectIds(&.{2}, try list(db, a, .{ .text = "hello", .tag = "misc" }));
    try expectIds(&.{ 1, 2, 3, 4 }, try list(db, a, .{ .text = "" }));
    // LIKE wildcards are plain characters.
    try expectIds(&.{3}, try list(db, a, .{ .text = "0%" }));
    try expectIds(&.{3}, try list(db, a, .{ .text = "_d" }));
    try expectIds(&.{}, try list(db, a, .{ .text = "%%" }));
    // Only ASCII letters are folded.
    try expectIds(&.{4}, try list(db, a, .{ .text = "Ünï" }));
    try expectIds(&.{}, try list(db, a, .{ .text = "ünï" }));
    try expectIds(&.{4}, try list(db, a, .{ .text = "ÉTÉ" }));
    try expectIds(&.{}, try list(db, a, .{ .text = "été" }));

    try expectIds(&.{ 3, 4 }, try list(db, a, .{ .after = 2 }));
    try expectIds(&.{ 1, 2, 3, 4 }, try list(db, a, .{ .after = -5 }));
    try expectIds(&.{}, try list(db, a, .{ .after = std.math.maxInt(i64) }));
    try expectIds(&.{ 1, 2 }, try list(db, a, .{ .limit = 2 }));
    try expectIds(&.{ 2, 3 }, try list(db, a, .{ .after = 1, .limit = 2 }));
    try expectIds(&.{2}, try list(db, a, .{ .after = 1, .tag = "greet", .text = "say" }));
}

test "list skips deleted notes" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes_db.insert(db, .{ .title = "a", .tags = &.{"x"} });
    _ = try notes_db.insert(db, .{ .title = "b", .tags = &.{"x"} });
    try db.run("DELETE FROM notes WHERE id = ?", .{1});
    try expectIds(&.{2}, try list(db, arena.allocator(), .{ .tag = "x" }));
}
