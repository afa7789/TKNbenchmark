//! The note model and the validation rules for client-supplied notes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

pub const max_title_len = 200;
pub const max_tag_len = 32;

/// A stored note, as returned to clients.
pub const Note = struct {
    id: i64,
    title: []const u8,
    body: []const u8,
    /// Unique and sorted ascending.
    tags: []const []const u8,
};

/// A validated and normalized note, as sent by a client to create or
/// replace a note.
pub const Input = struct {
    title: []const u8,
    body: []const u8 = "",
    /// Unique and sorted ascending.
    tags: []const []const u8 = &.{},
};

/// Explains why `parseInput` rejected a request body.
pub const Diagnostic = struct {
    message: []const u8 = "",
};

pub const ParseError = error{ OutOfMemory, InvalidInput };

/// Parses a JSON request body into a validated `Input`. On
/// `error.InvalidInput`, `diag.message` says what is wrong. The result may
/// reference `bytes` and memory from `arena`.
pub fn parseInput(arena: Allocator, bytes: []const u8, diag: *Diagnostic) ParseError!Input {
    const value = json.parseFromSliceLeaky(json.Value, arena, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return invalid(diag, "request body is not valid JSON"),
    };
    return inputFromJson(arena, value, diag);
}

/// Validates an already decoded JSON value; see `parseInput`.
pub fn inputFromJson(arena: Allocator, value: json.Value, diag: *Diagnostic) ParseError!Input {
    const object = switch (value) {
        .object => |o| o,
        else => return invalid(diag, "request body must be a JSON object"),
    };

    const raw_title = switch (object.get("title") orelse return invalid(diag, "title is required")) {
        .string => |s| s,
        else => return invalid(diag, "title must be a string"),
    };
    const title = std.mem.trim(u8, raw_title, &std.ascii.whitespace);
    // The JSON parser guarantees valid UTF-8.
    const title_len = std.unicode.utf8CountCodepoints(title) catch unreachable;
    if (title_len < 1 or title_len > max_title_len) {
        return invalid(diag, std.fmt.comptimePrint("title must be 1-{d} characters", .{max_title_len}));
    }

    const body = if (object.get("body")) |v| switch (v) {
        .string => |s| s,
        else => return invalid(diag, "body must be a string"),
    } else "";

    const tags: []const []const u8 = if (object.get("tags")) |v| switch (v) {
        .array => |array| try parseTags(arena, array.items, diag),
        else => return invalid(diag, "tags must be an array of strings"),
    } else &.{};

    return .{ .title = title, .body = body, .tags = tags };
}

fn parseTags(arena: Allocator, items: []const json.Value, diag: *Diagnostic) ParseError![]const []const u8 {
    const tags = try arena.alloc([]const u8, items.len);
    for (items, tags) |item, *tag| {
        tag.* = switch (item) {
            .string => |s| s,
            else => return invalid(diag, "tags must be an array of strings"),
        };
        if (!isValidTag(tag.*)) {
            return invalid(diag, std.fmt.comptimePrint(
                "each tag must be 1-{d} characters from a-z, 0-9 and -",
                .{max_tag_len},
            ));
        }
    }
    return normalizeTags(tags);
}

/// Whether `tag` is 1–32 characters from `a-z`, `0-9` and `-`.
pub fn isValidTag(tag: []const u8) bool {
    if (tag.len < 1 or tag.len > max_tag_len) return false;
    for (tag) |ch| switch (ch) {
        'a'...'z', '0'...'9', '-' => {},
        else => return false,
    };
    return true;
}

/// Sorts `tags` ascending and removes duplicates, in place. Returns the
/// unique prefix.
pub fn normalizeTags(tags: [][]const u8) [][]const u8 {
    std.mem.sort([]const u8, tags, {}, lessThan);
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

fn invalid(diag: *Diagnostic, message: []const u8) error{InvalidInput} {
    diag.message = message;
    return error.InvalidInput;
}

const testing = std.testing;

fn expectInvalid(bytes: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    try testing.expectError(error.InvalidInput, parseInput(arena.allocator(), bytes, &diag));
    try testing.expect(diag.message.len > 0);
}

test "parseInput applies defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const input = try parseInput(arena.allocator(), "{\"title\":\"first\"}", &diag);
    try testing.expectEqualStrings("first", input.title);
    try testing.expectEqualStrings("", input.body);
    try testing.expectEqual(0, input.tags.len);
}

test "parseInput trims the title and normalizes tags" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const input = try parseInput(
        arena.allocator(),
        "{\"title\":\"  second \",\"body\":\"text\",\"tags\":[\"work\",\"b-2\",\"work\",\"a\"],\"extra\":1}",
        &diag,
    );
    try testing.expectEqualStrings("second", input.title);
    try testing.expectEqualStrings("text", input.body);
    try testing.expectEqual(3, input.tags.len);
    try testing.expectEqualStrings("a", input.tags[0]);
    try testing.expectEqualStrings("b-2", input.tags[1]);
    try testing.expectEqualStrings("work", input.tags[2]);
}

test "parseInput counts title characters, not bytes" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const title = "é" ** max_title_len;
    const input = try parseInput(arena.allocator(), "{\"title\":\"" ++ title ++ "\"}", &diag);
    try testing.expectEqualStrings(title, input.title);
    try expectInvalid("{\"title\":\"" ++ "a" ** (max_title_len + 1) ++ "\"}");
}

test "parseInput rejects invalid bodies" {
    try expectInvalid("");
    try expectInvalid("{\"title\": ");
    try expectInvalid("[]");
    try expectInvalid("\"title\"");
    try expectInvalid("{}");
    try expectInvalid("{\"title\":null}");
    try expectInvalid("{\"title\":5}");
    try expectInvalid("{\"title\":\"   \"}");
    try expectInvalid("{\"title\":\"x\",\"body\":3}");
    try expectInvalid("{\"title\":\"x\",\"body\":null}");
    try expectInvalid("{\"title\":\"x\",\"tags\":\"a\"}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[1]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"Bad\"]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"\"]}");
    try expectInvalid("{\"title\":\"x\",\"tags\":[\"" ++ "a" ** (max_tag_len + 1) ++ "\"]}");
}

test isValidTag {
    try testing.expect(isValidTag("a"));
    try testing.expect(isValidTag("b-2"));
    try testing.expect(isValidTag("a" ** max_tag_len));
    try testing.expect(!isValidTag(""));
    try testing.expect(!isValidTag("A"));
    try testing.expect(!isValidTag("a b"));
    try testing.expect(!isValidTag("a_b"));
    try testing.expect(!isValidTag("a" ** (max_tag_len + 1)));
}
