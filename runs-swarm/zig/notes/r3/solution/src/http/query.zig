//! Parsing of URL query strings (`a=1&b=two%20words`).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Param = struct {
    /// Raw (still percent-encoded) name and value.
    name: []const u8,
    value: []const u8,
};

/// Iterates over the `name=value` pairs of a query string, without decoding.
/// A pair without `=` has an empty value; empty pairs are skipped.
pub const Iterator = struct {
    rest: []const u8,

    pub fn init(query: []const u8) Iterator {
        return .{ .rest = query };
    }

    pub fn next(it: *Iterator) ?Param {
        while (it.rest.len > 0) {
            const end = std.mem.indexOfScalar(u8, it.rest, '&') orelse it.rest.len;
            const pair = it.rest[0..end];
            it.rest = if (end < it.rest.len) it.rest[end + 1 ..] else "";
            if (pair.len == 0) continue;
            const eq = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
            return .{
                .name = pair[0..eq],
                .value = if (eq < pair.len) pair[eq + 1 ..] else "",
            };
        }
        return null;
    }
};

/// Returns the decoded value of the first parameter called `name`, or null
/// if the query has none.
pub fn get(arena: Allocator, query: []const u8, name: []const u8) Allocator.Error!?[]const u8 {
    var it: Iterator = .init(query);
    while (it.next()) |param| {
        const decoded_name = try decode(arena, param.name);
        if (std.mem.eql(u8, decoded_name, name)) return try decode(arena, param.value);
    }
    return null;
}

/// Decodes `+` as a space and `%XX` escapes. Malformed escapes are kept
/// verbatim. Returns `raw` itself when nothing needs decoding.
pub fn decode(arena: Allocator, raw: []const u8) Allocator.Error![]const u8 {
    if (std.mem.indexOfAny(u8, raw, "+%") == null) return raw;
    const buf = try arena.dupe(u8, raw);
    std.mem.replaceScalar(u8, buf, '+', ' ');
    return std.Uri.percentDecodeInPlace(buf);
}

const testing = std.testing;

test Iterator {
    var it: Iterator = .init("a=1&&b&c=x=y&=v");
    const expected = [_]Param{
        .{ .name = "a", .value = "1" },
        .{ .name = "b", .value = "" },
        .{ .name = "c", .value = "x=y" },
        .{ .name = "", .value = "v" },
    };
    for (expected) |want| {
        const got = it.next().?;
        try testing.expectEqualStrings(want.name, got.name);
        try testing.expectEqualStrings(want.value, got.value);
    }
    try testing.expectEqual(null, it.next());
}

test get {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try testing.expectEqualStrings("hello world", (try get(a, "q=hello+world&tag=x", "q")).?);
    try testing.expectEqualStrings("x", (try get(a, "q=hello+world&tag=x", "tag")).?);
    try testing.expectEqualStrings("a&b", (try get(a, "q=a%26b", "q")).?);
    try testing.expectEqualStrings("first", (try get(a, "q=first&q=second", "q")).?);
    try testing.expectEqualStrings("", (try get(a, "limit=", "limit")).?);
    try testing.expectEqualStrings("%zz", (try get(a, "q=%zz", "q")).?);
    try testing.expectEqual(null, try get(a, "q=1", "tag"));
    try testing.expectEqual(null, try get(a, "", "q"));
}
