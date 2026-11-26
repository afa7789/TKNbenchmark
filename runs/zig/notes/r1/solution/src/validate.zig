//! Validation of client input: note bodies, list query parameters, note ids.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Store = @import("Store.zig");

pub const max_title_len = 200;
pub const max_tag_len = 32;
pub const max_limit = 100;

/// Validation failure; `message` explains it and is suitable for clients.
pub const Failure = struct {
    message: []const u8,
};

pub const Error = error{Invalid} || Allocator.Error;

/// Parses and validates a JSON note body `{title, body?, tags?}`.
/// The result's strings are allocated in `arena`.
pub fn noteInput(arena: Allocator, json: []const u8, failure: *Failure) Error!Store.NoteInput {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{
        .duplicate_field_behavior = .use_last,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return fail(failure, "request body is not valid JSON"),
    };
    const obj = switch (root) {
        .object => |o| o,
        else => return fail(failure, "request body must be a JSON object"),
    };

    const raw_title = switch (obj.get("title") orelse return fail(failure, "title is required")) {
        .string => |s| s,
        else => return fail(failure, "title must be a string"),
    };
    const title = std.mem.trim(u8, raw_title, &std.ascii.whitespace);
    const title_len = std.unicode.utf8CountCodepoints(title) catch
        return fail(failure, "title must be valid UTF-8");
    if (title_len < 1 or title_len > max_title_len)
        return fail(failure, "title must be 1-200 characters");

    const body = if (obj.get("body")) |v| switch (v) {
        .string => |s| s,
        else => return fail(failure, "body must be a string"),
    } else "";

    const tags: []const []const u8 = if (obj.get("tags")) |v| switch (v) {
        .array => |a| try tagList(arena, a.items, failure),
        else => return fail(failure, "tags must be an array of strings"),
    } else &.{};

    return .{ .title = title, .body = body, .tags = tags };
}

/// Validates tags and returns them sorted ascending without duplicates.
fn tagList(arena: Allocator, values: []const std.json.Value, failure: *Failure) Error![]const []const u8 {
    const tags = try arena.alloc([]const u8, values.len);
    for (values, tags) |v, *t| {
        t.* = switch (v) {
            .string => |s| s,
            else => return fail(failure, "tags must be an array of strings"),
        };
        if (!isValidTag(t.*))
            return fail(failure, "each tag must be 1-32 characters from a-z, 0-9 and -");
    }
    std.mem.sort([]const u8, tags, {}, lessThan);

    var unique: usize = 0;
    for (tags) |t| {
        if (unique > 0 and std.mem.eql(u8, tags[unique - 1], t)) continue;
        tags[unique] = t;
        unique += 1;
    }
    return tags[0..unique];
}

pub fn isValidTag(tag: []const u8) bool {
    if (tag.len < 1 or tag.len > max_tag_len) return false;
    for (tag) |ch| switch (ch) {
        'a'...'z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// Parses the query string of `GET /notes` (without the leading `?`).
pub fn listFilter(arena: Allocator, query: []const u8, failure: *Failure) Error!Store.ListFilter {
    var filter: Store.ListFilter = .{};
    var seen: struct { tag: bool = false, q: bool = false, after: bool = false, limit: bool = false } = .{};

    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.findScalar(u8, pair, '=');
        const key = try percentDecode(arena, pair[0 .. eq orelse pair.len]);
        const value = try percentDecode(arena, if (eq) |i| pair[i + 1 ..] else "");

        // The first occurrence of a parameter wins.
        if (std.mem.eql(u8, key, "tag")) {
            if (seen.tag) continue;
            seen.tag = true;
            filter.tag = value;
        } else if (std.mem.eql(u8, key, "q")) {
            if (seen.q) continue;
            seen.q = true;
            filter.query = value;
        } else if (std.mem.eql(u8, key, "after")) {
            if (seen.after) continue;
            seen.after = true;
            filter.after = parseDecimal(i64, value) orelse
                return fail(failure, "after must be a non-negative integer");
        } else if (std.mem.eql(u8, key, "limit")) {
            if (seen.limit) continue;
            seen.limit = true;
            const limit = parseDecimal(u32, value) orelse 0;
            if (limit < 1 or limit > max_limit)
                return fail(failure, "limit must be an integer from 1 to 100");
            filter.limit = limit;
        }
    }
    return filter;
}

/// Parses a note id from a path segment; null unless it is a positive integer.
pub fn noteId(segment: []const u8) ?i64 {
    const id = parseDecimal(i64, segment) orelse return null;
    return if (id > 0) id else null;
}

/// Parses a string made only of ASCII digits; null on anything else or overflow.
fn parseDecimal(comptime T: type, s: []const u8) ?T {
    if (s.len == 0) return null;
    for (s) |ch| if (!std.ascii.isDigit(ch)) return null;
    return std.fmt.parseInt(T, s, 10) catch null;
}

/// Decodes `%XX` escapes and `+` (as space) of a URL query component.
/// Malformed escapes are kept literally.
fn percentDecode(arena: Allocator, s: []const u8) Allocator.Error![]const u8 {
    if (std.mem.findAny(u8, s, "%+") == null) return s;
    const out = try arena.alloc(u8, s.len);
    var i: usize = 0;
    var n: usize = 0;
    while (i < s.len) : (n += 1) {
        switch (s[i]) {
            '+' => {
                out[n] = ' ';
                i += 1;
            },
            '%' => {
                const escaped = if (i + 2 < s.len) decodeHex(s[i + 1 .. i + 3]) else null;
                if (escaped) |b| {
                    out[n] = b;
                    i += 3;
                } else {
                    out[n] = '%';
                    i += 1;
                }
            },
            else => |ch| {
                out[n] = ch;
                i += 1;
            },
        }
    }
    return out[0..n];
}

fn decodeHex(pair: []const u8) ?u8 {
    const hi = std.fmt.charToDigit(pair[0], 16) catch return null;
    const lo = std.fmt.charToDigit(pair[1], 16) catch return null;
    return hi << 4 | lo;
}

fn fail(failure: *Failure, message: []const u8) error{Invalid} {
    failure.message = message;
    return error.Invalid;
}

const testing = std.testing;

fn expectInvalidNote(json: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = undefined;
    try testing.expectError(error.Invalid, noteInput(arena.allocator(), json, &failure));
}

test "note input: defaults, trimming, tag normalization" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = undefined;

    const a = try noteInput(arena.allocator(), "{\"title\":\"  hi \"}", &failure);
    try testing.expectEqualStrings("hi", a.title);
    try testing.expectEqualStrings("", a.body);
    try testing.expectEqual(@as(usize, 0), a.tags.len);

    const b = try noteInput(arena.allocator(),
        \\{"title":"t","body":"b","tags":["work","b-2","work","a"]}
    , &failure);
    try testing.expectEqual(@as(usize, 3), b.tags.len);
    try testing.expectEqualStrings("a", b.tags[0]);
    try testing.expectEqualStrings("b-2", b.tags[1]);
    try testing.expectEqualStrings("work", b.tags[2]);

    // 200 multi-byte characters are fine, 201 are not.
    const ok_title = "é" ** 200;
    _ = try noteInput(arena.allocator(), "{\"title\":\"" ++ ok_title ++ "\"}", &failure);
    try expectInvalidNote("{\"title\":\"" ++ ok_title ++ "x\"}");
}

test "note input: rejects invalid bodies" {
    try expectInvalidNote("{\"title\": ");
    try expectInvalidNote("[]");
    try expectInvalidNote("{}");
    try expectInvalidNote("{\"title\":\"   \"}");
    try expectInvalidNote("{\"title\":5}");
    try expectInvalidNote("{\"title\":null}");
    try expectInvalidNote("{\"title\":\"x\",\"body\":3}");
    try expectInvalidNote("{\"title\":\"x\",\"tags\":[\"Bad\"]}");
    try expectInvalidNote("{\"title\":\"x\",\"tags\":[\"\"]}");
    try expectInvalidNote("{\"title\":\"x\",\"tags\":[1]}");
    try expectInvalidNote("{\"title\":\"x\",\"tags\":\"a\"}");
    try expectInvalidNote("{\"title\":\"x\",\"tags\":[\"" ++ "a" ** 33 ++ "\"]}");
}

test "list filter parsing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failure: Failure = undefined;

    const f = try listFilter(arena.allocator(), "tag=misc&q=hello%20there+x&after=2&limit=5", &failure);
    try testing.expectEqualStrings("misc", f.tag.?);
    try testing.expectEqualStrings("hello there x", f.query.?);
    try testing.expectEqual(@as(i64, 2), f.after);
    try testing.expectEqual(@as(u32, 5), f.limit);

    const d = try listFilter(arena.allocator(), "", &failure);
    try testing.expectEqual(@as(u32, 100), d.limit);
    try testing.expect(d.tag == null);

    for ([_][]const u8{ "limit=0", "limit=101", "limit=abc", "limit=", "after=x", "after=-1", "after=1.5" }) |q| {
        try testing.expectError(error.Invalid, listFilter(arena.allocator(), q, &failure));
    }
}

test "note ids" {
    try testing.expectEqual(@as(?i64, 7), noteId("7"));
    try testing.expectEqual(@as(?i64, null), noteId("0"));
    try testing.expectEqual(@as(?i64, null), noteId("-1"));
    try testing.expectEqual(@as(?i64, null), noteId("abc"));
    try testing.expectEqual(@as(?i64, null), noteId(""));
    try testing.expectEqual(@as(?i64, null), noteId("99999999999999999999999"));
}

test "percent decoding keeps malformed escapes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings("a%zz%", try percentDecode(arena.allocator(), "a%zz%"));
    try testing.expectEqualStrings("a/b", try percentDecode(arena.allocator(), "a%2Fb"));
}
