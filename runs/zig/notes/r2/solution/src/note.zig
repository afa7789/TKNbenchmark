//! The note model and validation of client-supplied note data.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_title_len = 200;
pub const max_tag_len = 32;

pub const Note = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    tags: []const []const u8,
};

/// Validated fields for creating or replacing a note.
pub const Input = struct {
    title: []const u8,
    body: []const u8,
    /// Unique and sorted ascending.
    tags: []const []const u8,
};

pub const ValidationError = error{
    InvalidJson,
    NotAnObject,
    InvalidTitle,
    InvalidBody,
    InvalidTags,
};

pub fn errorMessage(err: ValidationError) []const u8 {
    return switch (err) {
        error.InvalidJson => "body is not valid JSON",
        error.NotAnObject => "body must be a JSON object",
        error.InvalidTitle => "title must be a string of 1-200 characters",
        error.InvalidBody => "body must be a string",
        error.InvalidTags => "tags must be an array of 1-32 character strings of a-z, 0-9 and -",
    };
}

/// Parses and validates a JSON request body. Returned slices are allocated in
/// `arena` (or point into `json`), so it should be an arena allocator.
pub fn parseInput(arena: Allocator, json: []const u8) (ValidationError || Allocator.Error)!Input {
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{
        .duplicate_field_behavior = .use_last,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
    const object = switch (value) {
        .object => |o| o,
        else => return error.NotAnObject,
    };

    const title = switch (object.get("title") orelse return error.InvalidTitle) {
        .string => |s| std.mem.trim(u8, s, " \t\r\n"),
        else => return error.InvalidTitle,
    };
    const title_len = std.unicode.utf8CountCodepoints(title) catch return error.InvalidTitle;
    if (title_len < 1 or title_len > max_title_len) return error.InvalidTitle;

    const body = if (object.get("body")) |b| switch (b) {
        .string => |s| s,
        else => return error.InvalidBody,
    } else "";

    const tags: []const []const u8 = if (object.get("tags")) |t| switch (t) {
        .array => |array| try normalizeTags(arena, array.items),
        else => return error.InvalidTags,
    } else &.{};

    return .{ .title = title, .body = body, .tags = tags };
}

fn normalizeTags(arena: Allocator, items: []const std.json.Value) (ValidationError || Allocator.Error)![]const []const u8 {
    const tags = try arena.alloc([]const u8, items.len);
    for (items, tags) |item, *tag| {
        tag.* = switch (item) {
            .string => |s| s,
            else => return error.InvalidTags,
        };
        if (!isValidTag(tag.*)) return error.InvalidTags;
    }
    std.mem.sortUnstable([]const u8, tags, {}, lessThan);

    // Remove adjacent duplicates in place.
    var len: usize = 0;
    for (tags) |tag| {
        if (len > 0 and std.mem.eql(u8, tags[len - 1], tag)) continue;
        tags[len] = tag;
        len += 1;
    }
    return tags[0..len];
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

const testing = std.testing;

fn expectInvalid(expected: ValidationError, json: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(expected, parseInput(arena.allocator(), json));
}

test "parseInput applies defaults and normalizes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const minimal = try parseInput(arena.allocator(), "{\"title\":\"first\"}");
    try testing.expectEqualStrings("first", minimal.title);
    try testing.expectEqualStrings("", minimal.body);
    try testing.expectEqual(0, minimal.tags.len);

    const full = try parseInput(arena.allocator(),
        \\{"title":"  second  ","body":"text","tags":["work","b-2","work"],"extra":1}
    );
    try testing.expectEqualStrings("second", full.title);
    try testing.expectEqualStrings("text", full.body);
    try testing.expectEqual(2, full.tags.len);
    try testing.expectEqualStrings("b-2", full.tags[0]);
    try testing.expectEqualStrings("work", full.tags[1]);
}

test "title length counts characters, not bytes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const title = "é" ** 200;
    const json = try std.fmt.allocPrint(arena.allocator(), "{{\"title\":\"{s}\"}}", .{title});
    _ = try parseInput(arena.allocator(), json);

    const too_long = try std.fmt.allocPrint(arena.allocator(), "{{\"title\":\"{s}\"}}", .{"a" ** 201});
    try testing.expectError(error.InvalidTitle, parseInput(arena.allocator(), too_long));
}

test "parseInput rejects invalid input" {
    try expectInvalid(error.InvalidJson, "{\"title\": ");
    try expectInvalid(error.InvalidJson, "");
    try expectInvalid(error.NotAnObject, "[]");
    try expectInvalid(error.NotAnObject, "\"title\"");
    try expectInvalid(error.InvalidTitle, "{}");
    try expectInvalid(error.InvalidTitle, "{\"title\":null}");
    try expectInvalid(error.InvalidTitle, "{\"title\":5}");
    try expectInvalid(error.InvalidTitle, "{\"title\":\"   \"}");
    try expectInvalid(error.InvalidBody, "{\"title\":\"x\",\"body\":3}");
    try expectInvalid(error.InvalidBody, "{\"title\":\"x\",\"body\":null}");
    try expectInvalid(error.InvalidTags, "{\"title\":\"x\",\"tags\":[\"Bad\"]}");
    try expectInvalid(error.InvalidTags, "{\"title\":\"x\",\"tags\":[\"\"]}");
    try expectInvalid(error.InvalidTags, "{\"title\":\"x\",\"tags\":[1]}");
    try expectInvalid(error.InvalidTags, "{\"title\":\"x\",\"tags\":\"a\"}");
    try expectInvalid(error.InvalidTags, "{\"title\":\"x\",\"tags\":[\"" ++ "a" ** 33 ++ "\"]}");
}
