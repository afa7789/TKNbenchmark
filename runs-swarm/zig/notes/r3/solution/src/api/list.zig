//! GET /notes with its `tag`, `q`, `after` and `limit` query parameters.

const std = @import("std");
const Context = @import("../http/Context.zig");
const list_db = @import("../db/list.zig");

/// GET /notes
pub fn list(ctx: *Context) Context.Error!void {
    const filter = try readFilter(ctx) orelse return;
    const notes = blk: {
        const db = ctx.store.acquire();
        defer ctx.store.release();
        break :blk try list_db.list(db, ctx.arena, filter);
    };
    try ctx.sendJson(.ok, .{ .notes = notes });
}

/// Reads the filter from the query parameters. Answers 400 and returns null
/// if `after` or `limit` is invalid.
fn readFilter(ctx: *Context) Context.Error!?list_db.Filter {
    var filter: list_db.Filter = .{
        .tag = try ctx.queryParam("tag"),
        .text = try ctx.queryParam("q"),
    };
    if (try ctx.queryParam("after")) |text| {
        filter.after = parseAfter(text) orelse {
            try ctx.sendError(.bad_request, "after must be an integer");
            return null;
        };
    }
    if (try ctx.queryParam("limit")) |text| {
        filter.limit = parseLimit(text) orelse {
            try ctx.sendError(.bad_request, std.fmt.comptimePrint(
                "limit must be an integer from 1 to {d}",
                .{list_db.max_limit},
            ));
            return null;
        };
    }
    return filter;
}

/// Parses `after`: a decimal integer with an optional leading `-`.
fn parseAfter(text: []const u8) ?i64 {
    const digits = if (std.mem.startsWith(u8, text, "-")) text[1..] else text;
    if (!isDecimal(digits)) return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}

/// Parses `limit`: a decimal integer from 1 to `max_limit`.
fn parseLimit(text: []const u8) ?u32 {
    if (!isDecimal(text)) return null;
    const limit = std.fmt.parseInt(u32, text, 10) catch return null;
    return if (limit >= 1 and limit <= list_db.max_limit) limit else null;
}

/// Whether `text` is a non-empty run of ASCII digits. `std.fmt.parseInt`
/// also accepts a `+` sign and `_` separators, which are not valid here.
fn isDecimal(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |ch| if (!std.ascii.isDigit(ch)) return false;
    return true;
}

const testing = std.testing;

test parseAfter {
    try testing.expectEqual(@as(?i64, 0), parseAfter("0"));
    try testing.expectEqual(@as(?i64, 2), parseAfter("2"));
    try testing.expectEqual(@as(?i64, 7), parseAfter("007"));
    try testing.expectEqual(@as(?i64, -3), parseAfter("-3"));
    try testing.expectEqual(@as(?i64, std.math.maxInt(i64)), parseAfter("9223372036854775807"));
    try testing.expectEqual(@as(?i64, std.math.minInt(i64)), parseAfter("-9223372036854775808"));
    try testing.expectEqual(null, parseAfter("9223372036854775808"));
    try testing.expectEqual(null, parseAfter(""));
    try testing.expectEqual(null, parseAfter("-"));
    try testing.expectEqual(null, parseAfter("+1"));
    try testing.expectEqual(null, parseAfter("--1"));
    try testing.expectEqual(null, parseAfter("1_0"));
    try testing.expectEqual(null, parseAfter("1.5"));
    try testing.expectEqual(null, parseAfter(" 1"));
    try testing.expectEqual(null, parseAfter("abc"));
}

test parseLimit {
    try testing.expectEqual(@as(?u32, 1), parseLimit("1"));
    try testing.expectEqual(@as(?u32, 100), parseLimit("100"));
    try testing.expectEqual(@as(?u32, 5), parseLimit("05"));
    try testing.expectEqual(null, parseLimit("0"));
    try testing.expectEqual(null, parseLimit("101"));
    try testing.expectEqual(null, parseLimit("-1"));
    try testing.expectEqual(null, parseLimit("+1"));
    try testing.expectEqual(null, parseLimit("1_0"));
    try testing.expectEqual(null, parseLimit("99999999999999999999"));
    try testing.expectEqual(null, parseLimit(""));
    try testing.expectEqual(null, parseLimit("ten"));
}

test {
    _ = list_db;
}
