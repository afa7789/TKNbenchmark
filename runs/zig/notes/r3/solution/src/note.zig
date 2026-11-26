//! The note model and validation of client-supplied note payloads.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Note = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    tags: []const []const u8,
};

/// A validated note payload: trimmed title, and tags deduplicated and sorted.
pub const Input = struct {
    title: []const u8,
    body: []const u8,
    tags: []const []const u8,
};

pub const max_title_len = 200;
pub const max_tag_len = 32;

/// Result of parsing a payload: either a valid input or a client-facing error message.
pub const ParseResult = union(enum) {
    ok: Input,
    invalid: []const u8,
};

/// Parses and validates a JSON request body. All returned memory is owned by `arena`.
pub fn parseInput(arena: Allocator, json_text: []const u8) Allocator.Error!ParseResult {
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, json_text, .{
        .duplicate_field_behavior = .use_last,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .invalid = "body is not valid JSON" },
    };
    const obj = switch (value) {
        .object => |o| o,
        else => return .{ .invalid = "body must be a JSON object" },
    };

    const title_raw = switch (obj.get("title") orelse return .{ .invalid = "title is required" }) {
        .string => |s| s,
        else => return .{ .invalid = "title must be a string" },
    };
    const title = std.mem.trim(u8, title_raw, " \t\r\n");
    const title_len = std.unicode.utf8CountCodepoints(title) catch title.len;
    if (title_len < 1 or title_len > max_title_len)
        return .{ .invalid = "title must be 1-200 characters" };

    const body: []const u8 = if (obj.get("body")) |v| switch (v) {
        .string => |s| s,
        else => return .{ .invalid = "body must be a string" },
    } else "";

    var tags: []const []const u8 = &.{};
    if (obj.get("tags")) |v| {
        const items = switch (v) {
            .array => |a| a.items,
            else => return .{ .invalid = "tags must be an array of strings" },
        };
        const list = try arena.alloc([]const u8, items.len);
        for (items, list) |item, *slot| {
            slot.* = switch (item) {
                .string => |s| s,
                else => return .{ .invalid = "tags must be an array of strings" },
            };
            if (!isValidTag(slot.*))
                return .{ .invalid = "each tag must be 1-32 characters of a-z, 0-9 and -" };
        }
        tags = sortUnique(list);
    }

    return .{ .ok = .{ .title = title, .body = body, .tags = tags } };
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
    return std.mem.lessThan(u8, a, b);
}

/// Sorts `list` ascending in place and returns the prefix holding the unique elements.
fn sortUnique(list: [][]const u8) [][]const u8 {
    std.mem.sort([]const u8, list, {}, lessThan);
    var n: usize = 0;
    for (list) |tag| {
        if (n > 0 and std.mem.eql(u8, list[n - 1], tag)) continue;
        list[n] = tag;
        n += 1;
    }
    return list[0..n];
}

const testing = std.testing;

fn expectInvalid(text: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expect((try parseInput(arena.allocator(), text)) == .invalid);
}

test "parseInput normalizes title and tags" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const r = try parseInput(arena.allocator(),
        \\{"title":"  second  ","body":"some text","tags":["work","b-2","work"]}
    );
    const in = r.ok;
    try testing.expectEqualStrings("second", in.title);
    try testing.expectEqualStrings("some text", in.body);
    try testing.expectEqual(2, in.tags.len);
    try testing.expectEqualStrings("b-2", in.tags[0]);
    try testing.expectEqualStrings("work", in.tags[1]);
}

test "parseInput defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const in = (try parseInput(arena.allocator(), "{\"title\":\"x\"}")).ok;
    try testing.expectEqualStrings("", in.body);
    try testing.expectEqual(0, in.tags.len);
}

test "parseInput rejects invalid payloads" {
    try expectInvalid("{\"title\": ");
    try expectInvalid("");
    try expectInvalid("{\"title\":\"x\"} x");
    try expectInvalid("[]");
    try expectInvalid("{}");
    try expectInvalid("{\"title\":\"   \"}");
    try expectInvalid("{\"title\":5}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"Bad\"]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"\"]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":\"a\"}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[1]}");
    try expectInvalid("{\"title\":\"x\",\"body\":3}");
    try expectInvalid("{\"title\":\"x\",\"body\":null}");
    try expectInvalid("{\"title\":\"" ++ "a" ** 201 ++ "\"}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"" ++ "a" ** 33 ++ "\"]}");
}

test "title length counts characters, not bytes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const r = try parseInput(arena.allocator(), "{\"title\":\"" ++ "é" ** 200 ++ "\"}");
    try testing.expect(r == .ok);
}
