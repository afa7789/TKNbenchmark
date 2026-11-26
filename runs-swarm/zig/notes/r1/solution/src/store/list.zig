//! Data access for listing notes with filters (`GET /notes`).

const std = @import("std");
const Allocator = std.mem.Allocator;
const sqlite = @import("../db/sqlite.zig");
const Note = @import("../note.zig").Note;

pub const max_limit = 100;

pub const Filter = struct {
    /// Only notes that have this tag.
    tag: ?[]const u8 = null,
    /// Only notes whose title or body contains this text, ignoring ASCII case.
    text: ?[]const u8 = null,
    /// Only notes with an id greater than this.
    after: i64 = 0,
    /// At most this many notes, 1 to `max_limit`.
    limit: u32 = max_limit,
};

/// The notes matching `filter`, ordered by id ascending.
pub fn list(conn: sqlite.Conn, arena: Allocator, filter: Filter) ![]Note {
    std.debug.assert(filter.limit >= 1 and filter.limit <= max_limit);

    // One statement, so notes and tags come from one snapshot. Tags only
    // contain `a-z`, `0-9` and `-`, so a space separates them unambiguously.
    // SQLite's `lower` folds ASCII letters only, which is the case-folding the
    // text filter calls for; `instr` needs no escaping, unlike `LIKE`.
    var stmt = try conn.prepare(
        \\SELECT n.id, n.title, n.body,
        \\       (SELECT group_concat(t.tag, ' ' ORDER BY t.tag)
        \\          FROM note_tags t WHERE t.note_id = n.id)
        \\  FROM notes n
        \\ WHERE n.id > ?1
        \\   AND (?2 IS NULL OR EXISTS (
        \\          SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?2))
        \\   AND (?3 IS NULL
        \\        OR instr(lower(n.title), lower(?3)) > 0
        \\        OR instr(lower(n.body), lower(?3)) > 0)
        \\ ORDER BY n.id
        \\ LIMIT ?4
    );
    defer stmt.finalize();
    try stmt.bindAll(.{ filter.after, filter.tag, filter.text, filter.limit });

    var notes: std.ArrayList(Note) = .empty;
    while (try stmt.step()) {
        try notes.append(arena, .{
            .id = stmt.columnInt(0),
            .title = try stmt.columnTextDupe(arena, 1),
            .body = try stmt.columnTextDupe(arena, 2),
            .tags = try splitTags(arena, stmt.columnText(3)),
        });
    }
    return notes.toOwnedSlice(arena);
}

fn splitTags(arena: Allocator, joined: []const u8) Allocator.Error![]const []const u8 {
    if (joined.len == 0) return &.{};
    const tags = try arena.alloc([]const u8, std.mem.countScalar(u8, joined, ' ') + 1);
    var it = std.mem.splitScalar(u8, joined, ' ');
    for (tags) |*tag| tag.* = try arena.dupe(u8, it.next().?);
    return tags;
}

const testing = std.testing;
const notes_store = @import("notes.zig");

fn expectIds(conn: sqlite.Conn, filter: Filter, expected: []const i64) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const found = try list(conn, arena.allocator(), filter);
    const ids = try arena.allocator().alloc(i64, found.len);
    for (found, ids) |n, *id| id.* = n.id;
    try testing.expectEqualSlices(i64, expected, ids);
}

test "list filters and pages" {
    const conn = try notes_store.openTestDb();
    defer conn.close();

    _ = try notes_store.create(conn, .{ .title = "Hello world", .tags = &.{"greet"} });
    _ = try notes_store.create(conn, .{ .title = "other", .body = "say HELLO", .tags = &.{ "greet", "misc" } });
    _ = try notes_store.create(conn, .{ .title = "100% _done_" });
    _ = try notes_store.create(conn, .{ .title = "Ünïcode ÉTÉ" });

    try expectIds(conn, .{}, &.{ 1, 2, 3, 4 });
    try expectIds(conn, .{ .tag = "greet" }, &.{ 1, 2 });
    try expectIds(conn, .{ .tag = "misc" }, &.{2});
    try expectIds(conn, .{ .tag = "gre" }, &.{});
    try expectIds(conn, .{ .tag = "" }, &.{});
    try expectIds(conn, .{ .text = "hello" }, &.{ 1, 2 });
    try expectIds(conn, .{ .text = "HeLLo", .tag = "misc" }, &.{2});
    try expectIds(conn, .{ .text = "" }, &.{ 1, 2, 3, 4 });
    try expectIds(conn, .{ .text = "%" }, &.{3});
    try expectIds(conn, .{ .text = "_d" }, &.{3});
    try expectIds(conn, .{ .text = "o%" }, &.{});
    // Only ASCII letters are folded.
    try expectIds(conn, .{ .text = "été" }, &.{});
    try expectIds(conn, .{ .text = "ÉtÉ" }, &.{4});
    try expectIds(conn, .{ .text = "ünïcode" }, &.{});
    try expectIds(conn, .{ .after = 2 }, &.{ 3, 4 });
    try expectIds(conn, .{ .after = -7 }, &.{ 1, 2, 3, 4 });
    try expectIds(conn, .{ .after = std.math.maxInt(i64) }, &.{});
    try expectIds(conn, .{ .limit = 1 }, &.{1});
    try expectIds(conn, .{ .after = 1, .limit = 2 }, &.{ 2, 3 });
    try expectIds(conn, .{ .after = 1, .limit = 2, .text = "o" }, &.{ 2, 3 });
}

test "list returns full notes with sorted tags" {
    const conn = try notes_store.openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes_store.create(conn, .{ .title = "t", .body = "b", .tags = &.{ "a", "b-2", "z" } });
    _ = try notes_store.create(conn, .{ .title = "u" });

    const found = try list(conn, arena.allocator(), .{});
    try testing.expectEqual(2, found.len);
    try testing.expectEqualStrings("t", found[0].title);
    try testing.expectEqualStrings("b", found[0].body);
    try testing.expectEqual(3, found[0].tags.len);
    for ([_][]const u8{ "a", "b-2", "z" }, found[0].tags) |want, got| try testing.expectEqualStrings(want, got);
    try testing.expectEqual(0, found[1].tags.len);
}
