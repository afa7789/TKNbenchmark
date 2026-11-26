//! Data access for `GET /notes`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Store = @import("../Store.zig");
const sqlite = @import("../sqlite.zig");
const model = @import("../model.zig");
const notes = @import("notes.zig");
const Note = model.Note;

pub const max_limit = 100;

/// The filters of a listing; all of them are combined.
pub const Filter = struct {
    /// Only notes that have this tag.
    tag: ?[]const u8 = null,
    /// Only notes whose title or body contains this text, ignoring ASCII case.
    text: ?[]const u8 = null,
    /// Only notes with an id greater than this.
    after: ?i64 = null,
    /// At most this many notes, 1 to `max_limit`.
    limit: u32 = max_limit,
};

// SQLite's built-in `lower` folds ASCII letters only, which is exactly the
// case-insensitivity the spec asks for, and `instr` needs no escaping of
// `%` and `_` as `LIKE` would. Unset filters are bound as NULL.
const list_sql = "SELECT " ++ notes.note_columns ++ " FROM notes" ++
    \\
    \\WHERE (?1 IS NULL OR EXISTS
    \\        (SELECT 1 FROM note_tags WHERE note_tags.note_id = notes.id AND note_tags.tag = ?1))
    \\  AND (?2 IS NULL OR instr(lower(notes.title), lower(?2)) > 0
    \\                  OR instr(lower(notes.body), lower(?2)) > 0)
    \\  AND (?3 IS NULL OR notes.id > ?3)
    \\ORDER BY notes.id
    \\LIMIT ?4
;

/// The notes matching `filter`, ordered by id ascending, tags included.
/// All memory is owned by `arena`.
pub fn list(store: *Store, arena: Allocator, filter: Filter) ![]const Note {
    std.debug.assert(filter.limit >= 1 and filter.limit <= max_limit);

    const db = try store.acquire();
    defer store.release();

    var result: std.ArrayList(Note) = try .initCapacity(arena, filter.limit);
    {
        const stmt = try db.prepare(list_sql);
        defer stmt.finalize();
        try stmt.bindAll(.{ filter.tag, filter.text, filter.after, filter.limit });
        while (try stmt.step()) result.appendAssumeCapacity(try notes.scanNote(stmt, arena));
    }
    for (result.items) |*note| note.tags = try notes.loadTags(db, arena, note.id);
    return result.items;
}

const testing = std.testing;

fn expectIds(expected: []const i64, actual: []const Note) !void {
    var ids: [max_limit]i64 = undefined;
    for (actual, 0..) |note, i| ids[i] = note.id;
    try testing.expectEqualSlices(i64, expected, ids[0..actual.len]);
}

test "list filters by tag, text and id, and pages with a limit" {
    var store = try Store.open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try notes.create(&store, .{ .title = "Hello world", .tags = &.{"greet"} });
    _ = try notes.create(&store, .{ .title = "other", .body = "say HELLO", .tags = &.{ "greet", "misc" } });
    _ = try notes.create(&store, .{ .title = "100% done_ok" });

    const all = try list(&store, a, .{});
    try expectIds(&.{ 1, 2, 3 }, all);
    try testing.expectEqualStrings("misc", all[1].tags[1]);

    try expectIds(&.{2}, try list(&store, a, .{ .tag = "misc" }));
    try expectIds(&.{}, try list(&store, a, .{ .tag = "mis" }));
    try expectIds(&.{ 1, 2 }, try list(&store, a, .{ .text = "hELLo" }));
    try expectIds(&.{2}, try list(&store, a, .{ .text = "hello", .tag = "misc" }));
    try expectIds(&.{ 1, 2, 3 }, try list(&store, a, .{ .text = "" }));
    try expectIds(&.{3}, try list(&store, a, .{ .text = "0% d" }));
    try expectIds(&.{3}, try list(&store, a, .{ .text = "_" }));
    try expectIds(&.{}, try list(&store, a, .{ .text = "%%" }));
    try expectIds(&.{ 2, 3 }, try list(&store, a, .{ .after = 1 }));
    try expectIds(&.{ 1, 2, 3 }, try list(&store, a, .{ .after = -5 }));
    try expectIds(&.{2}, try list(&store, a, .{ .after = 1, .limit = 1 }));
    try expectIds(&.{}, try list(&store, a, .{ .after = std.math.maxInt(i64) }));
}
