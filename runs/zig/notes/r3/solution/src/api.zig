//! Request routing and the JSON API, independent of the HTTP transport.

const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;
const Store = @import("Store.zig");
const note = @import("note.zig");

pub const Response = struct {
    status: http.Status,
    body: []const u8,
    content_type: []const u8 = "application/json",
};

pub const Request = struct {
    method: http.Method,
    /// Request target: path plus optional `?query`.
    target: []const u8,
    body: []const u8 = "",
};

/// Handles one request. All allocations go to `arena`, which must outlive the response.
pub fn handle(store: *Store, arena: Allocator, req: Request) (Store.Error)!Response {
    const path, const query = splitTarget(req.target);

    if (std.mem.eql(u8, path, "/health")) {
        if (req.method != .GET) return methodNotAllowed();
        return .{ .status = .ok, .body = "ok", .content_type = "text/plain" };
    }
    if (std.mem.eql(u8, path, "/notes")) return switch (req.method) {
        .GET => listNotes(store, arena, query),
        .POST => createNote(store, arena, req.body),
        else => methodNotAllowed(),
    };
    if (std.mem.startsWith(u8, path, "/notes/")) {
        const rest = path["/notes/".len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) return notFound();
        switch (req.method) {
            .GET, .PUT, .DELETE => {},
            else => return methodNotAllowed(),
        }
        const id = parseId(rest) orelse return notFound();
        return switch (req.method) {
            .GET => getNote(store, arena, id),
            .PUT => updateNote(store, arena, id, req.body),
            .DELETE => deleteNote(store, id),
            else => unreachable,
        };
    }
    if (std.mem.eql(u8, path, "/stats")) {
        if (req.method != .GET) return methodNotAllowed();
        return stats(store, arena);
    }
    if (std.mem.eql(u8, path, "/tags")) {
        if (req.method != .GET) return methodNotAllowed();
        return tags(store, arena);
    }
    return notFound();
}

fn splitTarget(target: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, target, '?')) |i| return .{ target[0..i], target[i + 1 ..] };
    return .{ target, "" };
}

fn errorResponse(status: http.Status, comptime message: []const u8) Response {
    return .{ .status = status, .body = "{\"error\":\"" ++ message ++ "\"}" };
}

fn notFound() Response {
    return errorResponse(.not_found, "not found");
}

fn methodNotAllowed() Response {
    return errorResponse(.method_not_allowed, "method not allowed");
}

fn badRequest(arena: Allocator, message: []const u8) Allocator.Error!Response {
    return .{ .status = .bad_request, .body = try json(arena, .{ .@"error" = message }) };
}

fn json(arena: Allocator, value: anytype) Allocator.Error![]const u8 {
    return std.json.Stringify.valueAlloc(arena, value, .{});
}

/// Parses a positive decimal note id made only of digits.
fn parseId(text: []const u8) ?i64 {
    if (text.len == 0) return null;
    for (text) |ch| if (!std.ascii.isDigit(ch)) return null;
    const id = std.fmt.parseInt(i64, text, 10) catch return null;
    return if (id > 0) id else null;
}

/// Parses an optionally negative decimal integer made only of digits.
fn parseInteger(text: []const u8) ?i64 {
    const digits = if (std.mem.startsWith(u8, text, "-")) text[1..] else text;
    if (digits.len == 0) return null;
    for (digits) |ch| if (!std.ascii.isDigit(ch)) return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}

/// Decodes an `application/x-www-form-urlencoded` component.
fn decodeComponent(arena: Allocator, raw: []const u8) Allocator.Error![]const u8 {
    const buf = try arena.dupe(u8, raw);
    std.mem.replaceScalar(u8, buf, '+', ' ');
    return std.Uri.percentDecodeInPlace(buf);
}

const ListParams = union(enum) {
    ok: Store.Filter,
    invalid: []const u8,
};

fn parseListParams(arena: Allocator, query: []const u8) Allocator.Error!ListParams {
    var filter: Store.Filter = .{};
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        if (pair.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, pair, '=');
        const key = try decodeComponent(arena, pair[0 .. eq orelse pair.len]);
        const value = try decodeComponent(arena, if (eq) |i| pair[i + 1 ..] else "");
        if (std.mem.eql(u8, key, "tag")) {
            filter.tag = value;
        } else if (std.mem.eql(u8, key, "q")) {
            filter.query = value;
        } else if (std.mem.eql(u8, key, "after")) {
            filter.after = parseInteger(value) orelse return .{ .invalid = "after must be an integer" };
        } else if (std.mem.eql(u8, key, "limit")) {
            const n = parseInteger(value) orelse return .{ .invalid = "limit must be an integer from 1 to 100" };
            if (n < 1 or n > 100) return .{ .invalid = "limit must be an integer from 1 to 100" };
            filter.limit = @intCast(n);
        }
    }
    return .{ .ok = filter };
}

fn listNotes(store: *Store, arena: Allocator, query: []const u8) Store.Error!Response {
    const filter = switch (try parseListParams(arena, query)) {
        .ok => |f| f,
        .invalid => |msg| return badRequest(arena, msg),
    };
    const notes = try store.list(arena, filter);
    return .{ .status = .ok, .body = try json(arena, .{ .notes = notes }) };
}

fn createNote(store: *Store, arena: Allocator, body: []const u8) Store.Error!Response {
    const input = switch (try note.parseInput(arena, body)) {
        .ok => |in| in,
        .invalid => |msg| return badRequest(arena, msg),
    };
    const created = try store.create(arena, input);
    return .{ .status = .created, .body = try json(arena, created) };
}

fn getNote(store: *Store, arena: Allocator, id: i64) Store.Error!Response {
    const found = try store.get(arena, id) orelse return notFound();
    return .{ .status = .ok, .body = try json(arena, found) };
}

fn updateNote(store: *Store, arena: Allocator, id: i64, body: []const u8) Store.Error!Response {
    const input = switch (try note.parseInput(arena, body)) {
        .ok => |in| in,
        .invalid => |msg| return badRequest(arena, msg),
    };
    const updated = try store.update(arena, id, input) orelse return notFound();
    return .{ .status = .ok, .body = try json(arena, updated) };
}

fn deleteNote(store: *Store, id: i64) Store.Error!Response {
    if (!try store.delete(id)) return notFound();
    return .{ .status = .no_content, .body = "" };
}

fn stats(store: *Store, arena: Allocator) Store.Error!Response {
    const count = try store.noteCount();
    const counts = try store.tagCounts(arena);

    var out: std.Io.Writer.Allocating = .init(arena);
    var w: std.json.Stringify = .{ .writer = &out.writer };
    writeStats(&w, count, counts) catch return error.OutOfMemory;
    return .{ .status = .ok, .body = out.written() };
}

fn writeStats(w: *std.json.Stringify, count: i64, counts: []const Store.TagCount) std.json.Stringify.Error!void {
    try w.beginObject();
    try w.objectField("notes");
    try w.write(count);
    try w.objectField("tags");
    try w.beginObject();
    for (counts) |tc| {
        try w.objectField(tc.tag);
        try w.write(tc.count);
    }
    try w.endObject();
    try w.endObject();
}

fn tags(store: *Store, arena: Allocator) Store.Error!Response {
    const counts = try store.tagCounts(arena);
    return .{ .status = .ok, .body = try json(arena, .{ .tags = counts }) };
}

const testing = std.testing;

const TestEnv = struct {
    arena: std.heap.ArenaAllocator,
    store: Store,

    fn init() !TestEnv {
        return .{ .arena = .init(testing.allocator), .store = try Store.open(testing.io, ":memory:") };
    }

    fn deinit(env: *TestEnv) void {
        env.store.close();
        env.arena.deinit();
    }

    fn call(env: *TestEnv, method: http.Method, target: []const u8, body: []const u8) !Response {
        return handle(&env.store, env.arena.allocator(), .{ .method = method, .target = target, .body = body });
    }

    fn expect(env: *TestEnv, method: http.Method, target: []const u8, body: []const u8, status: http.Status, want: ?[]const u8) !void {
        const res = try env.call(method, target, body);
        try testing.expectEqual(status, res.status);
        if (want) |w| try testing.expectEqualStrings(w, res.body);
    }
};

test "routing and status codes" {
    var env: TestEnv = try .init();
    defer env.deinit();

    try env.expect(.GET, "/health", "", .ok, "ok");
    try env.expect(.GET, "/nope", "", .not_found, null);
    try env.expect(.DELETE, "/notes", "", .method_not_allowed, null);
    try env.expect(.POST, "/stats", "", .method_not_allowed, null);
    try env.expect(.GET, "/notes/abc", "", .not_found, null);
    try env.expect(.GET, "/notes/0", "", .not_found, null);
    try env.expect(.GET, "/notes/-1", "", .not_found, null);
    try env.expect(.GET, "/notes/99999999999999999999", "", .not_found, null);
    try env.expect(.POST, "/notes", "{\"title\":\"a b\",\"tags\":[\"z\",\"a\"]}", .created,
        \\{"id":1,"title":"a b","body":"","tags":["a","z"]}
    );
    try env.expect(.GET, "/notes/1?x=1", "", .ok, null);
    try env.expect(.PUT, "/notes/1", "{\"title\":\"\"}", .bad_request, null);
    try env.expect(.PUT, "/notes/2", "{\"title\":\"x\"}", .not_found, null);
    try env.expect(.GET, "/notes?limit=0", "", .bad_request, null);
    try env.expect(.GET, "/notes?limit=101", "", .bad_request, null);
    try env.expect(.GET, "/notes?after=x", "", .bad_request, null);
    try env.expect(.GET, "/notes?q=A+B", "", .ok,
        \\{"notes":[{"id":1,"title":"a b","body":"","tags":["a","z"]}]}
    );
    try env.expect(.GET, "/notes?q=a%20c", "", .ok, "{\"notes\":[]}");
    try env.expect(.GET, "/stats", "", .ok, "{\"notes\":1,\"tags\":{\"a\":1,\"z\":1}}");
    try env.expect(.GET, "/tags", "", .ok,
        \\{"tags":[{"tag":"a","count":1},{"tag":"z","count":1}]}
    );
    try env.expect(.DELETE, "/notes/1", "", .no_content, "");
    try env.expect(.GET, "/stats", "", .ok, "{\"notes\":0,\"tags\":{}}");
}

test parseInteger {
    try testing.expectEqual(-3, parseInteger("-3"));
    try testing.expectEqual(null, parseInteger("+3"));
    try testing.expectEqual(null, parseInteger(""));
    try testing.expectEqual(null, parseInteger("1_0"));
}
