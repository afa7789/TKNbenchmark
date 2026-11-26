//! The note model and validation of client input. Shared by every endpoint
//! that accepts or returns notes.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_title_len = 200;
pub const max_tag_len = 32;

/// A stored note, as returned to clients.
pub const Note = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    /// Sorted ascending, without duplicates.
    tags: []const []const u8,
};

/// Validated, normalized fields of a note sent by a client (`POST /notes`,
/// `PUT /notes/{id}`).
pub const Input = struct {
    /// Trimmed, 1–200 characters.
    title: []const u8,
    body: []const u8 = "",
    /// Valid tags, sorted ascending, without duplicates.
    tags: []const []const u8 = &.{},
};

pub const InputError = error{
    InvalidJson,
    NotAnObject,
    InvalidTitle,
    InvalidBody,
    InvalidTags,
};

/// The client-facing message for a validation error.
pub fn errorMessage(err: InputError) []const u8 {
    return switch (err) {
        error.InvalidJson => "request body is not valid JSON",
        error.NotAnObject => "request body must be a JSON object",
        error.InvalidTitle => "title must be a string of 1 to 200 characters",
        error.InvalidBody => "body must be a string",
        error.InvalidTags => "tags must be an array of strings of 1 to 32 characters from a-z, 0-9 and -",
    };
}

/// Parses and validates a JSON note `{title, body?, tags?}`. Unknown fields are
/// ignored; of a repeated field the last occurrence wins, as in most JSON
/// parsers. All returned memory is owned by `arena`.
pub fn parseInput(arena: Allocator, json: []const u8) (InputError || Allocator.Error)!Input {
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{
        .duplicate_field_behavior = .use_last,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
    const object = switch (value) {
        .object => |object| object,
        else => return error.NotAnObject,
    };

    const title = switch (object.get("title") orelse return error.InvalidTitle) {
        .string => |s| try normalizeTitle(s),
        else => return error.InvalidTitle,
    };
    const body = if (object.get("body")) |body| switch (body) {
        .string => |s| s,
        else => return error.InvalidBody,
    } else "";
    const tags = if (object.get("tags")) |tags| switch (tags) {
        .array => |array| try normalizeTags(arena, array.items),
        else => return error.InvalidTags,
    } else &.{};

    return .{ .title = title, .body = body, .tags = tags };
}

/// Strips leading and trailing whitespace and checks the length, counted in
/// Unicode code points.
pub fn normalizeTitle(raw: []const u8) error{InvalidTitle}![]const u8 {
    const title = std.mem.trim(u8, raw, &std.ascii.whitespace);
    const len = std.unicode.utf8CountCodepoints(title) catch return error.InvalidTitle;
    if (len < 1 or len > max_title_len) return error.InvalidTitle;
    return title;
}

pub fn isValidTag(tag: []const u8) bool {
    if (tag.len < 1 or tag.len > max_tag_len) return false;
    for (tag) |ch| switch (ch) {
        'a'...'z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

/// Validates the tags, then sorts them and removes duplicates.
fn normalizeTags(arena: Allocator, values: []const std.json.Value) (error{InvalidTags} || Allocator.Error)![]const []const u8 {
    const tags = try arena.alloc([]const u8, values.len);
    for (values, tags) |value, *tag| {
        tag.* = switch (value) {
            .string => |s| if (isValidTag(s)) s else return error.InvalidTags,
            else => return error.InvalidTags,
        };
    }
    std.mem.sortUnstable([]const u8, tags, {}, lessThan);

    var len: usize = 0;
    for (tags) |tag| {
        if (len > 0 and std.mem.eql(u8, tags[len - 1], tag)) continue;
        tags[len] = tag;
        len += 1;
    }
    return tags[0..len];
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

const testing = std.testing;

fn expectInput(json: []const u8, expected: Input) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const input = try parseInput(arena.allocator(), json);
    try testing.expectEqualStrings(expected.title, input.title);
    try testing.expectEqualStrings(expected.body, input.body);
    try testing.expectEqual(expected.tags.len, input.tags.len);
    for (expected.tags, input.tags) |want, got| try testing.expectEqualStrings(want, got);
}

fn expectInputError(json: []const u8, expected: InputError) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(expected, parseInput(arena.allocator(), json));
}

test "parseInput applies defaults" {
    try expectInput("{\"title\":\"first\"}", .{ .title = "first" });
}

test "parseInput normalizes title and tags" {
    try expectInput(
        \\{"title":"  second  ","body":"some text","tags":["work","b-2","work"],"extra":1}
    , .{ .title = "second", .body = "some text", .tags = &.{ "b-2", "work" } });
}

test "parseInput takes the last of repeated fields" {
    try expectInput(
        \\{"title":1,"title":"last","tags":["a"],"tags":["b"]}
    , .{ .title = "last", .tags = &.{"b"} });
}

test "parseInput counts title length in characters" {
    try expectInput("{\"title\":\"" ++ "é" ** 200 ++ "\"}", .{ .title = "é" ** 200 });
    try expectInputError("{\"title\":\"" ++ "a" ** 201 ++ "\"}", error.InvalidTitle);
}

test "parseInput rejects invalid input" {
    try expectInputError("{\"title\": ", error.InvalidJson);
    try expectInputError("[]", error.NotAnObject);
    try expectInputError("\"title\"", error.NotAnObject);
    try expectInputError("{}", error.InvalidTitle);
    try expectInputError("{\"title\":\"   \"}", error.InvalidTitle);
    try expectInputError("{\"title\":5}", error.InvalidTitle);
    try expectInputError("{\"title\":\"x\",\"body\":3}", error.InvalidBody);
    try expectInputError("{\"title\":\"x\",\"body\":null}", error.InvalidBody);
    try expectInputError("{\"title\":\"x\",\"tags\":\"a\"}", error.InvalidTags);
    try expectInputError("{\"title\":\"x\",\"tags\":[\"Bad\"]}", error.InvalidTags);
    try expectInputError("{\"title\":\"x\",\"tags\":[\"\"]}", error.InvalidTags);
    try expectInputError("{\"title\":\"x\",\"tags\":[1]}", error.InvalidTags);
    try expectInputError("{\"title\":\"x\",\"tags\":[\"" ++ "a" ** 33 ++ "\"]}", error.InvalidTags);
}

test isValidTag {
    try testing.expect(isValidTag("a-0"));
    try testing.expect(isValidTag("a" ** 32));
    try testing.expect(!isValidTag(""));
    try testing.expect(!isValidTag("a" ** 33));
    try testing.expect(!isValidTag("A"));
    try testing.expect(!isValidTag("a_b"));
    try testing.expect(!isValidTag("a b"));
}
