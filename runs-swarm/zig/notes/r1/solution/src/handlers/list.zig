//! `GET /notes` with the optional query parameters `tag`, `q`, `after` and
//! `limit`.

const std = @import("std");
const api = @import("../api.zig");
const query = @import("../query.zig");
const store = @import("../store/list.zig");
const Response = api.Response;

/// 200 with `{"notes": [note, ...]}` ordered by id, 400 on an invalid `limit`
/// or `after`.
pub fn list(ctx: *const api.Context, req: api.Request) !Response {
    const filter = parseFilter(ctx.arena, req.query) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.InvalidLimit => return Response.badRequest(ctx.arena, "limit must be an integer from 1 to 100"),
        error.InvalidAfter => return Response.badRequest(ctx.arena, "after must be an integer"),
    };

    const conn = try ctx.acquireDb();
    defer ctx.releaseDb(conn);
    const notes = try store.list(conn, ctx.arena, filter);
    return Response.json(ctx.arena, .ok, .{ .notes = notes });
}

const FilterError = error{ InvalidLimit, InvalidAfter } || std.mem.Allocator.Error;

/// Builds the filter from the query string. Unknown parameters are ignored;
/// if a parameter is repeated, the last occurrence wins.
fn parseFilter(arena: std.mem.Allocator, raw_query: []const u8) FilterError!store.Filter {
    var filter: store.Filter = .{};
    var params: query.Iterator = .init(arena, raw_query);
    while (try params.next()) |param| {
        if (std.mem.eql(u8, param.name, "tag")) {
            filter.tag = param.value;
        } else if (std.mem.eql(u8, param.name, "q")) {
            filter.text = param.value;
        } else if (std.mem.eql(u8, param.name, "after")) {
            filter.after = parseAfter(param.value) orelse return error.InvalidAfter;
        } else if (std.mem.eql(u8, param.name, "limit")) {
            filter.limit = parseLimit(param.value) orelse return error.InvalidLimit;
        }
    }
    return filter;
}

/// A decimal integer: digits with an optional leading `-`. Values beyond the
/// range of ids saturate, which keeps "greater than" exact.
fn parseAfter(text: []const u8) ?i64 {
    const negative = std.mem.startsWith(u8, text, "-");
    const digits = if (negative) text[1..] else text;
    if (!isDigits(digits)) return null;
    return std.fmt.parseInt(i64, text, 10) catch |err| switch (err) {
        error.Overflow => if (negative) std.math.minInt(i64) else std.math.maxInt(i64),
        error.InvalidCharacter => unreachable,
    };
}

/// A decimal integer from 1 to `store.max_limit`, digits only.
fn parseLimit(text: []const u8) ?u32 {
    if (!isDigits(text)) return null;
    const limit = std.fmt.parseInt(u32, text, 10) catch return null;
    return if (limit >= 1 and limit <= store.max_limit) limit else null;
}

/// Non-empty and only ASCII digits. `std.fmt.parseInt` alone would also
/// accept a sign and `_` separators.
fn isDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |ch| if (!std.ascii.isDigit(ch)) return false;
    return true;
}

const testing = std.testing;
const TestEnv = @import("../TestEnv.zig");

test parseAfter {
    try testing.expectEqual(0, parseAfter("0"));
    try testing.expectEqual(42, parseAfter("0042"));
    try testing.expectEqual(-3, parseAfter("-3"));
    try testing.expectEqual(std.math.maxInt(i64), parseAfter("99999999999999999999"));
    try testing.expectEqual(std.math.minInt(i64), parseAfter("-99999999999999999999"));
    for ([_][]const u8{ "", "-", "+1", "1.5", "1e3", "1_000", " 1", "1 ", "abc", "--1", "0x10" }) |text| {
        try testing.expectEqual(null, parseAfter(text));
    }
}

test parseLimit {
    try testing.expectEqual(1, parseLimit("1"));
    try testing.expectEqual(100, parseLimit("100"));
    try testing.expectEqual(7, parseLimit("007"));
    for ([_][]const u8{ "", "0", "101", "-1", "+5", "5.0", "1_0", "abc", "99999999999999999999" }) |text| {
        try testing.expectEqual(null, parseLimit(text));
    }
}

test "GET /notes lists and filters" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.GET, "/notes", "", .ok, "{\"notes\":[]}");

    try env.expect(.POST, "/notes", "{\"title\":\"Hello world\",\"tags\":[\"greet\"]}", .created, null);
    try env.expect(.POST, "/notes", "{\"title\":\"other\",\"body\":\"say HELLO\",\"tags\":[\"misc\",\"greet\"]}", .created, null);
    try env.expect(.POST, "/notes", "{\"title\":\"nothing\"}", .created, null);

    try env.expect(.GET, "/notes", "", .ok,
        \\{"notes":[
        \\ {"id":1,"title":"Hello world","body":"","tags":["greet"]},
        \\ {"id":2,"title":"other","body":"say HELLO","tags":["greet","misc"]},
        \\ {"id":3,"title":"nothing","body":"","tags":[]}]}
    );
    try env.expect(.GET, "/notes?tag=misc", "", .ok,
        \\{"notes":[{"id":2,"title":"other","body":"say HELLO","tags":["greet","misc"]}]}
    );
    try env.expect(.GET, "/notes?q=hello&tag=greet&limit=1", "", .ok,
        \\{"notes":[{"id":1,"title":"Hello world","body":"","tags":["greet"]}]}
    );
    try env.expect(.GET, "/notes?q=o+w", "", .ok,
        \\{"notes":[{"id":1,"title":"Hello world","body":"","tags":["greet"]}]}
    );
    try env.expect(.GET, "/notes?q=SAY%20h", "", .ok,
        \\{"notes":[{"id":2,"title":"other","body":"say HELLO","tags":["greet","misc"]}]}
    );
    try env.expect(.GET, "/notes?after=1&limit=1", "", .ok,
        \\{"notes":[{"id":2,"title":"other","body":"say HELLO","tags":["greet","misc"]}]}
    );
    try env.expect(.GET, "/notes?after=3", "", .ok, "{\"notes\":[]}");
    try env.expect(.GET, "/notes?tag=Bad", "", .ok, "{\"notes\":[]}");
    try env.expect(.GET, "/notes?other=1", "", .ok, null);
}

test "GET /notes rejects an invalid limit or after" {
    var env = try TestEnv.init();
    defer env.deinit();

    try env.expect(.GET, "/notes?limit=0", "", .bad_request,
        \\{"error":"limit must be an integer from 1 to 100"}
    );
    try env.expect(.GET, "/notes?limit=101", "", .bad_request, null);
    try env.expect(.GET, "/notes?limit=", "", .bad_request, null);
    try env.expect(.GET, "/notes?limit=x", "", .bad_request, null);
    try env.expect(.GET, "/notes?after=x", "", .bad_request,
        \\{"error":"after must be an integer"}
    );
    try env.expect(.GET, "/notes?after=", "", .bad_request, null);
    try env.expect(.GET, "/notes?after=1.5&limit=5", "", .bad_request, null);
}
