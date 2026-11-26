//! Request routing and handlers, independent of the HTTP transport.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Method = std.http.Method;
const Status = std.http.Status;

const note = @import("note.zig");
const Store = @import("Store.zig");

pub const Response = struct {
    status: Status,
    body: []const u8,
    content_type: []const u8 = "application/json",
    /// Value of the `Allow` header for 405 responses.
    allow: ?[]const u8 = null,
};

pub const Request = struct {
    method: Method,
    /// Path plus optional query string, as sent by the client.
    target: []const u8,
    body: []const u8 = "",
};

/// Handles one request. All allocations go to `arena`, which must outlive the
/// returned response.
pub fn handle(store: *Store, arena: Allocator, req: Request) Allocator.Error!Response {
    return route(store, arena, req) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SqliteError => return errorResponse(arena, .internal_server_error, "database error"),
        error.WriteFailed => return error.OutOfMemory,
    };
}

const HandlerError = Store.Error || std.Io.Writer.Error;

fn route(store: *Store, arena: Allocator, req: Request) HandlerError!Response {
    const path, const query = splitTarget(req.target);

    if (std.mem.eql(u8, path, "/health")) {
        if (!isGet(req.method)) return methodNotAllowed(arena, "GET");
        return .{ .status = .ok, .body = "ok", .content_type = "text/plain" };
    }
    if (std.mem.eql(u8, path, "/notes")) return switch (req.method) {
        .GET, .HEAD => listNotes(store, arena, query),
        .POST => createNote(store, arena, req.body),
        else => methodNotAllowed(arena, "GET, POST"),
    };
    if (std.mem.startsWith(u8, path, "/notes/")) {
        const id = parseId(path["/notes/".len..]) orelse return notFound(arena);
        return switch (req.method) {
            .GET, .HEAD => getNote(store, arena, id),
            .PUT => updateNote(store, arena, id, req.body),
            .DELETE => deleteNote(store, arena, id),
            else => methodNotAllowed(arena, "GET, PUT, DELETE"),
        };
    }
    if (std.mem.eql(u8, path, "/stats")) {
        if (!isGet(req.method)) return methodNotAllowed(arena, "GET");
        return stats(store, arena);
    }
    if (std.mem.eql(u8, path, "/tags")) {
        if (!isGet(req.method)) return methodNotAllowed(arena, "GET");
        return tags(store, arena);
    }
    return notFound(arena);
}

fn createNote(store: *Store, arena: Allocator, body: []const u8) HandlerError!Response {
    const input = note.parseInput(arena, body) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => |e| return errorResponse(arena, .bad_request, note.errorMessage(e)),
    };
    const created = try store.create(arena, input);
    return jsonResponse(arena, .created, created);
}

fn getNote(store: *Store, arena: Allocator, id: i64) HandlerError!Response {
    const found = try store.get(arena, id) orelse return notFound(arena);
    return jsonResponse(arena, .ok, found);
}

fn updateNote(store: *Store, arena: Allocator, id: i64, body: []const u8) HandlerError!Response {
    const input = note.parseInput(arena, body) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => |e| return errorResponse(arena, .bad_request, note.errorMessage(e)),
    };
    const updated = try store.update(arena, id, input) orelse return notFound(arena);
    return jsonResponse(arena, .ok, updated);
}

fn deleteNote(store: *Store, arena: Allocator, id: i64) HandlerError!Response {
    if (!try store.delete(id)) return notFound(arena);
    return .{ .status = .no_content, .body = "" };
}

fn listNotes(store: *Store, arena: Allocator, query: []const u8) HandlerError!Response {
    const filter = parseFilter(arena, query) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidLimit => return errorResponse(arena, .bad_request, "limit must be an integer from 1 to 100"),
        error.InvalidAfter => return errorResponse(arena, .bad_request, "after must be a non-negative integer"),
    };
    const notes = try store.list(arena, filter);
    return jsonResponse(arena, .ok, .{ .notes = notes });
}

fn stats(store: *Store, arena: Allocator) HandlerError!Response {
    const s = try store.stats(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    var json: std.json.Stringify = .{ .writer = &out.writer };
    try json.beginObject();
    try json.objectField("notes");
    try json.write(s.notes);
    try json.objectField("tags");
    try json.beginObject();
    for (s.tags) |t| {
        try json.objectField(t.tag);
        try json.write(t.count);
    }
    try json.endObject();
    try json.endObject();
    return .{ .status = .ok, .body = out.written() };
}

fn tags(store: *Store, arena: Allocator) HandlerError!Response {
    const counts = try store.tagsByCount(arena);
    return jsonResponse(arena, .ok, .{ .tags = counts });
}

fn isGet(method: Method) bool {
    return method == .GET or method == .HEAD;
}

fn jsonResponse(arena: Allocator, status: Status, value: anytype) Allocator.Error!Response {
    return .{ .status = status, .body = try std.json.Stringify.valueAlloc(arena, value, .{}) };
}

fn errorResponse(arena: Allocator, status: Status, message: []const u8) Allocator.Error!Response {
    return jsonResponse(arena, status, .{ .@"error" = message });
}

fn notFound(arena: Allocator) Allocator.Error!Response {
    return errorResponse(arena, .not_found, "not found");
}

fn methodNotAllowed(arena: Allocator, allow: []const u8) Allocator.Error!Response {
    var response = try errorResponse(arena, .method_not_allowed, "method not allowed");
    response.allow = allow;
    return response;
}

/// Splits a request target into its path and query string.
fn splitTarget(target: []const u8) struct { []const u8, []const u8 } {
    const without_fragment = target[0 .. std.mem.indexOfScalar(u8, target, '#') orelse target.len];
    const q = std.mem.indexOfScalar(u8, without_fragment, '?') orelse
        return .{ without_fragment, "" };
    return .{ without_fragment[0..q], without_fragment[q + 1 ..] };
}

/// Parses a note id: a positive decimal integer without sign.
fn parseId(text: []const u8) ?i64 {
    const id = parseUnsigned(text) orelse return null;
    return if (id > 0) id else null;
}

fn parseUnsigned(text: []const u8) ?i64 {
    if (text.len == 0) return null;
    for (text) |ch| if (!std.ascii.isDigit(ch)) return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}

const FilterError = error{ InvalidLimit, InvalidAfter } || Allocator.Error;

fn parseFilter(arena: Allocator, query: []const u8) FilterError!Store.Filter {
    var filter: Store.Filter = .{};
    var seen: struct { tag: bool = false, q: bool = false, after: bool = false, limit: bool = false } = .{};

    var params = std.mem.splitScalar(u8, query, '&');
    while (params.next()) |param| {
        if (param.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, param, '=');
        const key = try percentDecode(arena, param[0 .. eq orelse param.len]);
        const value = try percentDecode(arena, if (eq) |i| param[i + 1 ..] else "");

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
            filter.after = parseUnsigned(value) orelse return error.InvalidAfter;
        } else if (std.mem.eql(u8, key, "limit")) {
            if (seen.limit) continue;
            seen.limit = true;
            const limit = parseUnsigned(value) orelse return error.InvalidLimit;
            if (limit < 1 or limit > 100) return error.InvalidLimit;
            filter.limit = @intCast(limit);
        }
    }
    return filter;
}

/// Decodes `application/x-www-form-urlencoded` text: `+` is a space and `%XX`
/// is a byte. Malformed escapes are kept literally.
fn percentDecode(arena: Allocator, text: []const u8) Allocator.Error![]const u8 {
    if (std.mem.indexOfAny(u8, text, "%+") == null) return text;
    const out = try arena.alloc(u8, text.len);
    var len: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (len += 1) {
        if (text[i] == '+') {
            out[len] = ' ';
            i += 1;
        } else if (text[i] == '%' and i + 2 < text.len and hexByte(text[i + 1 ..][0..2]) != null) {
            out[len] = hexByte(text[i + 1 ..][0..2]).?;
            i += 3;
        } else {
            out[len] = text[i];
            i += 1;
        }
    }
    return out[0..len];
}

fn hexByte(digits: *const [2]u8) ?u8 {
    const hi = std.fmt.charToDigit(digits[0], 16) catch return null;
    const lo = std.fmt.charToDigit(digits[1], 16) catch return null;
    return hi << 4 | lo;
}

const testing = std.testing;

test splitTarget {
    const path, const query = splitTarget("/notes?tag=a&q=b");
    try testing.expectEqualStrings("/notes", path);
    try testing.expectEqualStrings("tag=a&q=b", query);
    const bare, const empty = splitTarget("/notes");
    try testing.expectEqualStrings("/notes", bare);
    try testing.expectEqualStrings("", empty);
}

test parseId {
    try testing.expectEqual(12, parseId("12"));
    try testing.expectEqual(null, parseId("0"));
    try testing.expectEqual(null, parseId("-1"));
    try testing.expectEqual(null, parseId("+1"));
    try testing.expectEqual(null, parseId("abc"));
    try testing.expectEqual(null, parseId(""));
    try testing.expectEqual(null, parseId("1/"));
    try testing.expectEqual(null, parseId("99999999999999999999"));
}

test percentDecode {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("hello world", try percentDecode(a, "hello+world"));
    try testing.expectEqualStrings("a b&c", try percentDecode(a, "a%20b%26c"));
    try testing.expectEqualStrings("100%", try percentDecode(a, "100%"));
    try testing.expectEqualStrings("%zz", try percentDecode(a, "%zz"));
    try testing.expectEqualStrings("%4", try percentDecode(a, "%4"));
}

test parseFilter {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const f = try parseFilter(a, "tag=x&q=Hi+there&after=3&limit=10&other=1");
    try testing.expectEqualStrings("x", f.tag.?);
    try testing.expectEqualStrings("Hi there", f.query.?);
    try testing.expectEqual(3, f.after);
    try testing.expectEqual(10, f.limit);

    const defaults = try parseFilter(a, "");
    try testing.expectEqual(null, defaults.tag);
    try testing.expectEqual(100, defaults.limit);

    try testing.expectError(error.InvalidLimit, parseFilter(a, "limit=0"));
    try testing.expectError(error.InvalidLimit, parseFilter(a, "limit=101"));
    try testing.expectError(error.InvalidLimit, parseFilter(a, "limit="));
    try testing.expectError(error.InvalidLimit, parseFilter(a, "limit=abc"));
    try testing.expectError(error.InvalidAfter, parseFilter(a, "after=-1"));
    try testing.expectError(error.InvalidAfter, parseFilter(a, "after=x"));
}

fn expectStatus(store: *Store, status: Status, method: Method, target: []const u8, body: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const res = try handle(store, arena.allocator(), .{ .method = method, .target = target, .body = body });
    try testing.expectEqual(status, res.status);
}

test "routing" {
    var store: Store = try .open(testing.io, ":memory:");
    defer store.close();

    try expectStatus(&store, .ok, .GET, "/health", "");
    try expectStatus(&store, .method_not_allowed, .POST, "/health", "");
    try expectStatus(&store, .not_found, .GET, "/nope", "");
    try expectStatus(&store, .method_not_allowed, .DELETE, "/notes", "");
    try expectStatus(&store, .created, .POST, "/notes", "{\"title\":\"a\",\"tags\":[\"t\"]}");
    try expectStatus(&store, .bad_request, .POST, "/notes", "{\"title\":");
    try expectStatus(&store, .ok, .GET, "/notes/1", "");
    try expectStatus(&store, .not_found, .GET, "/notes/2", "");
    try expectStatus(&store, .not_found, .GET, "/notes/abc", "");
    try expectStatus(&store, .method_not_allowed, .POST, "/notes/1", "");
    try expectStatus(&store, .bad_request, .PUT, "/notes/1", "{}");
    try expectStatus(&store, .not_found, .PUT, "/notes/5", "{\"title\":\"x\"}");
    try expectStatus(&store, .ok, .GET, "/notes?tag=t&limit=5", "");
    try expectStatus(&store, .bad_request, .GET, "/notes?limit=0", "");
    try expectStatus(&store, .ok, .GET, "/stats", "");
    try expectStatus(&store, .ok, .GET, "/tags", "");
    try expectStatus(&store, .no_content, .DELETE, "/notes/1", "");
    try expectStatus(&store, .not_found, .DELETE, "/notes/1", "");
}

test "stats body" {
    var store: Store = try .open(testing.io, ":memory:");
    defer store.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    _ = try handle(&store, a, .{ .method = .POST, .target = "/notes", .body = "{\"title\":\"a\",\"tags\":[\"y\",\"x\"]}" });
    _ = try handle(&store, a, .{ .method = .POST, .target = "/notes", .body = "{\"title\":\"b\",\"tags\":[\"x\"]}" });
    const s = try handle(&store, a, .{ .method = .GET, .target = "/stats" });
    try testing.expectEqualStrings("{\"notes\":2,\"tags\":{\"x\":2,\"y\":1}}", s.body);
    const t = try handle(&store, a, .{ .method = .GET, .target = "/tags" });
    try testing.expectEqualStrings("{\"tags\":[{\"tag\":\"x\",\"count\":2},{\"tag\":\"y\",\"count\":1}]}", t.body);
}
