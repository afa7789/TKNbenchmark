//! Parsing of URL query strings (`application/x-www-form-urlencoded`).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Param = struct {
    name: []const u8,
    value: []const u8,
};

/// Iterates over the `name=value` pairs of a raw query string (without `?`),
/// percent-decoding names and values and turning `+` into a space. Empty
/// pairs (`a=1&&b=2`) are skipped; a pair without `=` has an empty value.
/// Malformed percent escapes are kept literally.
pub const Iterator = struct {
    pairs: std.mem.SplitIterator(u8, .scalar),
    arena: Allocator,

    pub fn init(arena: Allocator, query: []const u8) Iterator {
        return .{ .pairs = std.mem.splitScalar(u8, query, '&'), .arena = arena };
    }

    /// The next parameter; its strings are owned by the arena.
    pub fn next(it: *Iterator) Allocator.Error!?Param {
        while (it.pairs.next()) |pair| {
            if (pair.len == 0) continue;
            const name, const value = if (std.mem.indexOfScalar(u8, pair, '=')) |i|
                .{ pair[0..i], pair[i + 1 ..] }
            else
                .{ pair, "" };
            return .{ .name = try decode(it.arena, name), .value = try decode(it.arena, value) };
        }
        return null;
    }
};

/// Decodes one form-encoded component into newly allocated memory.
pub fn decode(arena: Allocator, encoded: []const u8) Allocator.Error![]const u8 {
    if (std.mem.indexOfAny(u8, encoded, "%+") == null) return encoded;

    const out = try arena.alloc(u8, encoded.len);
    var len: usize = 0;
    var i: usize = 0;
    while (i < encoded.len) : (len += 1) {
        switch (encoded[i]) {
            '+' => {
                out[len] = ' ';
                i += 1;
            },
            '%' => if (escapedByte(encoded[i + 1 ..])) |byte| {
                out[len] = byte;
                i += 3;
            } else {
                out[len] = '%';
                i += 1;
            },
            else => |ch| {
                out[len] = ch;
                i += 1;
            },
        }
    }
    return out[0..len];
}

/// The byte encoded by the two hex digits that start `rest`, if any.
fn escapedByte(rest: []const u8) ?u8 {
    if (rest.len < 2) return null;
    const hi = std.fmt.charToDigit(rest[0], 16) catch return null;
    const lo = std.fmt.charToDigit(rest[1], 16) catch return null;
    return hi << 4 | lo;
}

const testing = std.testing;

fn expectParams(query: []const u8, expected: []const Param) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var it: Iterator = .init(arena.allocator(), query);
    for (expected) |want| {
        const got = (try it.next()) orelse return error.TestExpectedMoreParams;
        try testing.expectEqualStrings(want.name, got.name);
        try testing.expectEqualStrings(want.value, got.value);
    }
    try testing.expectEqual(null, try it.next());
}

test Iterator {
    try expectParams("", &.{});
    try expectParams("a=1", &.{.{ .name = "a", .value = "1" }});
    try expectParams("a=1&&b=&c", &.{
        .{ .name = "a", .value = "1" },
        .{ .name = "b", .value = "" },
        .{ .name = "c", .value = "" },
    });
    try expectParams("q=a=b", &.{.{ .name = "q", .value = "a=b" }});
    try expectParams("q%3D=x%26y+z", &.{.{ .name = "q=", .value = "x&y z" }});
}

test decode {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("plain", try decode(a, "plain"));
    try testing.expectEqualStrings("a b c", try decode(a, "a+b%20c"));
    try testing.expectEqualStrings("é+", try decode(a, "%C3%a9%2B"));
    try testing.expectEqualStrings("100%", try decode(a, "100%"));
    try testing.expectEqualStrings("%4", try decode(a, "%4"));
    try testing.expectEqualStrings("%zz%", try decode(a, "%zz%"));
}
