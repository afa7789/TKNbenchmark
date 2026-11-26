//! POST /notes and GET /notes/{id}, plus request helpers shared by the
//! other note endpoints.

const std = @import("std");
const Context = @import("../http/Context.zig");
const note = @import("../note.zig");
const notes_db = @import("../db/notes.zig");

/// POST /notes
pub fn create(ctx: *Context) Context.Error!void {
    const input = try readInput(ctx) orelse return;
    const created = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk try notes_db.insert(db, input);
    };
    try ctx.sendJson(.created, created);
}

/// GET /notes/{id}
pub fn get(ctx: *Context) Context.Error!void {
    const id = try idParam(ctx) orelse return;
    const found = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk try notes_db.get(db, ctx.arena, id);
    };
    if (found) |n| return ctx.sendJson(.ok, n);
    try sendNotFound(ctx);
}

/// Reads and validates a note from the request body. Answers 400 and
/// returns null if it is invalid.
pub fn readInput(ctx: *Context) Context.Error!?note.Input {
    const body = try ctx.readBody();
    var diag: note.Diagnostic = .{};
    return note.parseInput(ctx.arena, body, &diag) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.InvalidInput => {
            try ctx.sendError(.bad_request, diag.message);
            return null;
        },
    };
}

/// The `{id}` path parameter. Answers 404 and returns null if it is not a
/// positive integer, since no note can have such an id.
pub fn idParam(ctx: *Context) Context.Error!?i64 {
    if (parseId(ctx.param("id"))) |id| return id;
    try sendNotFound(ctx);
    return null;
}

pub fn sendNotFound(ctx: *Context) Context.Error!void {
    try ctx.sendError(.not_found, "note not found");
}

/// Parses a note id: a positive decimal integer without sign.
pub fn parseId(text: []const u8) ?i64 {
    if (text.len == 0) return null;
    for (text) |ch| if (!std.ascii.isDigit(ch)) return null;
    const id = std.fmt.parseInt(i64, text, 10) catch return null;
    return if (id > 0) id else null;
}

test parseId {
    try std.testing.expectEqual(@as(?i64, 1), parseId("1"));
    try std.testing.expectEqual(@as(?i64, 42), parseId("42"));
    try std.testing.expectEqual(@as(?i64, std.math.maxInt(i64)), parseId("9223372036854775807"));
    try std.testing.expectEqual(null, parseId("9223372036854775808"));
    try std.testing.expectEqual(null, parseId("0"));
    try std.testing.expectEqual(null, parseId("-1"));
    try std.testing.expectEqual(null, parseId("+1"));
    try std.testing.expectEqual(null, parseId("abc"));
    try std.testing.expectEqual(null, parseId("1a"));
    try std.testing.expectEqual(null, parseId("1_0"));
    try std.testing.expectEqual(null, parseId(""));
}

test {
    _ = notes_db;
}
