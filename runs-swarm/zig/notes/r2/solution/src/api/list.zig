//! `GET /notes` with the optional query parameters `tag`, `q`, `after` and
//! `limit` (see SPEC.md).

const std = @import("std");
const Allocator = std.mem.Allocator;
const web = @import("../web.zig");
const model = @import("../model.zig");
const store = @import("../store/list.zig");

/// `GET /notes`: 200 and `{"notes": [note, ...]}` ordered by id, or 400.
pub fn list(req: *web.Request) !web.Response {
    var diag: model.Diagnostic = .{};
    const filter = parseFilter(req.arena, req.query, &diag) catch |err| switch (err) {
        error.InvalidInput => return web.jsonError(req.arena, .bad_request, diag.message),
        else => |e| return e,
    };
    const notes = try store.list(req.store, req.arena, filter);
    return web.json(req.arena, .ok, .{ .notes = notes });
}

/// Parses the query string of `GET /notes`. Unknown parameters are ignored;
/// when a parameter is repeated, the last value wins.
pub fn parseFilter(arena: Allocator, query: []const u8, diag: *model.Diagnostic) model.ParseError!store.Filter {
    var filter: store.Filter = .{};
    var pairs = std.mem.splitScalar(u8, query, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, pair, '=');
        const name = try formDecode(arena, pair[0 .. eq orelse pair.len]);
        const value = try formDecode(arena, if (eq) |i| pair[i + 1 ..] else "");

        if (std.mem.eql(u8, name, "tag")) {
            filter.tag = value;
        } else if (std.mem.eql(u8, name, "q")) {
            filter.text = value;
        } else if (std.mem.eql(u8, name, "after")) {
            filter.after = parseInteger(i64, value) orelse
                return invalid(diag, "after must be an integer");
        } else if (std.mem.eql(u8, name, "limit")) {
            const limit = parseInteger(u32, value) orelse 0;
            if (limit < 1 or limit > store.max_limit) return invalid(diag, "limit must be an integer from 1 to 100");
            filter.limit = limit;
        }
    }
    return filter;
}

/// A base-10 integer: an optional `-` followed by digits only (no `+`,
/// underscores or spaces). Null if malformed or out of range for `T`.
fn parseInteger(comptime T: type, text: []const u8) ?T {
    const digits = if (std.mem.startsWith(u8, text, "-")) text[1..] else text;
    if (digits.len == 0) return null;
    for (digits) |ch| if (!std.ascii.isDigit(ch)) return null;
    return std.fmt.parseInt(T, text, 10) catch null;
}

/// Decodes an `application/x-www-form-urlencoded` component: `+` is a
/// space and `%XX` a byte. A `%` not followed by two hex digits is kept as is.
fn formDecode(arena: Allocator, encoded: []const u8) Allocator.Error![]const u8 {
    if (std.mem.indexOfAny(u8, encoded, "%+") == null) return encoded;
    const out = try arena.alloc(u8, encoded.len);
    var len: usize = 0;
    var i: usize = 0;
    while (i < encoded.len) : (len += 1) {
        const ch = encoded[i];
        if (ch == '%' and i + 2 < encoded.len and
            std.ascii.isHex(encoded[i + 1]) and std.ascii.isHex(encoded[i + 2]))
        {
            out[len] = std.fmt.parseInt(u8, encoded[i + 1 ..][0..2], 16) catch unreachable;
            i += 3;
        } else {
            out[len] = if (ch == '+') ' ' else ch;
            i += 1;
        }
    }
    return out[0..len];
}

fn invalid(diag: *model.Diagnostic, message: []const u8) error{InvalidInput} {
    diag.message = message;
    return error.InvalidInput;
}

const testing = std.testing;

test formDecode {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("plain", try formDecode(a, "plain"));
    try testing.expectEqualStrings("a b c", try formDecode(a, "a+b%20c"));
    try testing.expectEqualStrings("100%", try formDecode(a, "100%25"));
    try testing.expectEqualStrings("é&=", try formDecode(a, "%C3%A9%26%3d"));
    try testing.expectEqualStrings("%zz%4", try formDecode(a, "%zz%4"));
    try testing.expectEqualStrings("%", try formDecode(a, "%"));
}

test parseInteger {
    try testing.expectEqual(@as(?i64, 42), parseInteger(i64, "42"));
    try testing.expectEqual(@as(?i64, -3), parseInteger(i64, "-3"));
    try testing.expectEqual(@as(?i64, 7), parseInteger(i64, "007"));
    try testing.expectEqual(null, parseInteger(i64, ""));
    try testing.expectEqual(null, parseInteger(i64, "-"));
    try testing.expectEqual(null, parseInteger(i64, "+1"));
    try testing.expectEqual(null, parseInteger(i64, "1_0"));
    try testing.expectEqual(null, parseInteger(i64, "1.5"));
    try testing.expectEqual(null, parseInteger(i64, " 1"));
    try testing.expectEqual(null, parseInteger(i64, "99999999999999999999"));
    try testing.expectEqual(null, parseInteger(u32, "-1"));
}

test parseFilter {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diag: model.Diagnostic = .{};

    const defaults = try parseFilter(a, "", &diag);
    try testing.expectEqual(store.Filter{}, defaults);

    const full = try parseFilter(a, "tag=work&q=Hello+there&after=2&limit=10&other=x&&flag", &diag);
    try testing.expectEqualStrings("work", full.tag.?);
    try testing.expectEqualStrings("Hello there", full.text.?);
    try testing.expectEqual(@as(?i64, 2), full.after);
    try testing.expectEqual(@as(u32, 10), full.limit);

    try testing.expectEqual(@as(u32, 100), (try parseFilter(a, "limit=100", &diag)).limit);
    try testing.expectEqual(@as(u32, 1), (try parseFilter(a, "limit=1", &diag)).limit);
    try testing.expectEqualStrings("", (try parseFilter(a, "q=", &diag)).text.?);

    const bad = [_][]const u8{
        "limit=0",           "limit=101", "limit=-1", "limit=abc", "limit=",     "limit", "limit=1.0",
        "limit=99999999999", "after=x",   "after=",   "after=1e3", "after=%2B1",
    };
    for (bad) |query| {
        diag = .{};
        try testing.expectError(error.InvalidInput, parseFilter(a, query, &diag));
        try testing.expect(diag.message.len > 0);
    }
}
