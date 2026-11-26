//! The note type and the validation of note input (`POST /notes`, `PUT /notes/{id}`).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_title_len = 200;
pub const max_tag_len = 32;

/// A stored note, serialized as-is in responses.
pub const Note = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    /// Sorted ascending, without duplicates.
    tags: []const []const u8,
};

/// A validated `{title, body?, tags?}` request body.
pub const NoteInput = struct {
    /// Trimmed, 1–200 characters.
    title: []const u8,
    body: []const u8 = "",
    /// Valid tags, sorted ascending, without duplicates.
    tags: []const []const u8 = &.{},
};

/// Why an input was rejected; `message` is meant for the client.
pub const Diagnostic = struct {
    message: []const u8 = "",
};

pub const ParseError = error{ InvalidInput, OutOfMemory };

/// Parses and validates a note request body. All returned memory is owned by
/// `arena`. On `error.InvalidInput`, `diag.message` says why.
pub fn parseNoteInput(arena: Allocator, json_text: []const u8, diag: *Diagnostic) ParseError!NoteInput {
    // Duplicate keys are valid JSON; like most parsers, the last one wins.
    const options: std.json.ParseOptions = .{ .duplicate_field_behavior = .use_last };
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, json_text, options) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return invalid(diag, "body is not valid JSON"),
    };
    const object = switch (root) {
        .object => |o| o,
        else => return invalid(diag, "body must be a JSON object"),
    };

    const title = switch (object.get("title") orelse return invalid(diag, "title is required")) {
        .string => |s| std.mem.trim(u8, s, " "),
        else => return invalid(diag, "title must be a string"),
    };
    const title_len = std.unicode.utf8CountCodepoints(title) catch title.len;
    if (title_len == 0) return invalid(diag, "title must not be empty");
    if (title_len > max_title_len) return invalid(diag, "title must be at most 200 characters");

    const body = if (object.get("body")) |value| switch (value) {
        .string => |s| s,
        else => return invalid(diag, "body must be a string"),
    } else "";

    const tags = if (object.get("tags")) |value| switch (value) {
        .array => |array| try normalizeTags(arena, array.items, diag),
        else => return invalid(diag, "tags must be an array of strings"),
    } else &.{};

    return .{ .title = title, .body = body, .tags = tags };
}

/// A tag is 1–32 characters from `a-z`, `0-9` and `-`.
pub fn isValidTag(tag: []const u8) bool {
    if (tag.len == 0 or tag.len > max_tag_len) return false;
    for (tag) |ch| switch (ch) {
        'a'...'z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

fn normalizeTags(arena: Allocator, values: []const std.json.Value, diag: *Diagnostic) ParseError![]const []const u8 {
    const tags = try arena.alloc([]const u8, values.len);
    for (values, tags) |value, *tag| {
        tag.* = switch (value) {
            .string => |s| s,
            else => return invalid(diag, "tags must be an array of strings"),
        };
        if (!isValidTag(tag.*)) return invalid(diag, "each tag must be 1-32 characters from a-z, 0-9 and -");
    }
    std.mem.sortUnstable([]const u8, tags, {}, lessThan);

    // Drop adjacent duplicates in place.
    var len: usize = 0;
    for (tags) |tag| {
        if (len > 0 and std.mem.eql(u8, tags[len - 1], tag)) continue;
        tags[len] = tag;
        len += 1;
    }
    return tags[0..len];
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn invalid(diag: *Diagnostic, message: []const u8) error{InvalidInput} {
    diag.message = message;
    return error.InvalidInput;
}

const testing = std.testing;

fn expectInvalid(json_text: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.InvalidInput, parseNoteInput(arena.allocator(), json_text, &diag));
    try testing.expect(diag.message.len > 0);
}

test "parseNoteInput applies defaults, trims the title and normalizes tags" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};

    const minimal = try parseNoteInput(arena.allocator(), "{\"title\":\"first\"}", &diag);
    try testing.expectEqualStrings("first", minimal.title);
    try testing.expectEqualStrings("", minimal.body);
    try testing.expectEqual(@as(usize, 0), minimal.tags.len);

    const full = try parseNoteInput(
        arena.allocator(),
        "{\"title\":\"  second  \",\"body\":\"text\",\"tags\":[\"work\",\"b-2\",\"work\"],\"extra\":1}",
        &diag,
    );
    try testing.expectEqualStrings("second", full.title);
    try testing.expectEqualStrings("text", full.body);
    try testing.expectEqual(@as(usize, 2), full.tags.len);
    try testing.expectEqualStrings("b-2", full.tags[0]);
    try testing.expectEqualStrings("work", full.tags[1]);

    const repeated = try parseNoteInput(arena.allocator(), "{\"title\":\"a\",\"title\":\"b\"}", &diag);
    try testing.expectEqualStrings("b", repeated.title);
}

test "parseNoteInput counts title length in characters" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    // 200 two-byte characters: 400 bytes, still valid.
    const title = "é" ** 200;
    const input = try parseNoteInput(arena.allocator(), "{\"title\":\"" ++ title ++ "\"}", &diag);
    try testing.expectEqualStrings(title, input.title);
    try expectInvalid("{\"title\":\"" ++ "a" ** 201 ++ "\"}");
}

test "parseNoteInput rejects invalid input" {
    try expectInvalid("{\"title\": ");
    try expectInvalid("[]");
    try expectInvalid("\"title\"");
    try expectInvalid("{}");
    try expectInvalid("{\"title\":3}");
    try expectInvalid("{\"title\":\"   \"}");
    try expectInvalid("{\"title\":\"x\",\"body\":3}");
    try expectInvalid("{\"title\":\"x\",\"body\":null}");
    try expectInvalid("{\"title\":\"x\",\"tags\":\"a\"}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[1]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"Bad\"]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"\"]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"" ++ "a" ** 33 ++ "\"]}");
}

test isValidTag {
    try testing.expect(isValidTag("a"));
    try testing.expect(isValidTag("b-2"));
    try testing.expect(isValidTag("a" ** 32));
    try testing.expect(!isValidTag(""));
    try testing.expect(!isValidTag("a" ** 33));
    try testing.expect(!isValidTag("Work"));
    try testing.expect(!isValidTag("a_b"));
    try testing.expect(!isValidTag("a b"));
}
