//! HTTP routing and handlers, independent of the transport.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Status = std.http.Status;
const Method = std.http.Method;
const Stringify = std.json.Stringify;
const Store = @import("Store.zig");
const validate = @import("validate.zig");

pub const Request = struct {
    method: Method,
    /// Request target: path plus optional `?query`.
    target: []const u8,
    body: []const u8,
};

pub const Response = struct {
    status: Status,
    content_type: []const u8 = "application/json",
    body: []const u8 = "",
};

/// Computes the response to a request. Only storage failures and allocation
/// failures are returned as errors.
pub fn handle(store: *Store, arena: Allocator, req: Request) Store.Error!Response {
    const qmark = std.mem.findScalar(u8, req.target, '?');
    const path = req.target[0 .. qmark orelse req.target.len];
    const query = if (qmark) |i| req.target[i + 1 ..] else "";

    if (std.mem.eql(u8, path, "/health")) {
        if (req.method != .GET) return methodNotAllowed(arena);
        return .{ .status = .ok, .content_type = "text/plain; charset=utf-8", .body = "ok" };
    }
    if (std.mem.eql(u8, path, "/notes")) return switch (req.method) {
        .GET => listNotes(store, arena, query),
        .POST => createNote(store, arena, req.body),
        else => methodNotAllowed(arena),
    };
    if (std.mem.startsWith(u8, path, "/notes/")) {
        const segment = path["/notes/".len..];
        const id = validate.noteId(segment) orelse return notFound(arena);
        return switch (req.method) {
            .GET => getNote(store, arena, id),
            .PUT => updateNote(store, arena, id, req.body),
            .DELETE => deleteNote(store, id, arena),
            else => methodNotAllowed(arena),
        };
    }
    if (std.mem.eql(u8, path, "/stats")) {
        if (req.method != .GET) return methodNotAllowed(arena);
        return stats(store, arena);
    }
    if (std.mem.eql(u8, path, "/tags")) {
        if (req.method != .GET) return methodNotAllowed(arena);
        return tags(store, arena);
    }
    return notFound(arena);
}

fn createNote(store: *Store, arena: Allocator, body: []const u8) Store.Error!Response {
    var failure: validate.Failure = undefined;
    const input = validate.noteInput(arena, body, &failure) catch |err| switch (err) {
        error.Invalid => return errorResponse(arena, .bad_request, failure.message),
        error.OutOfMemory => return error.OutOfMemory,
    };
    const note = try store.create(input);
    return json(arena, .created, note);
}

fn getNote(store: *Store, arena: Allocator, id: i64) Store.Error!Response {
    const note = try store.get(arena, id) orelse return notFound(arena);
    return json(arena, .ok, note);
}

fn updateNote(store: *Store, arena: Allocator, id: i64, body: []const u8) Store.Error!Response {
    var failure: validate.Failure = undefined;
    const input = validate.noteInput(arena, body, &failure) catch |err| switch (err) {
        error.Invalid => return errorResponse(arena, .bad_request, failure.message),
        error.OutOfMemory => return error.OutOfMemory,
    };
    const note = try store.update(id, input) orelse return notFound(arena);
    return json(arena, .ok, note);
}

fn deleteNote(store: *Store, id: i64, arena: Allocator) Store.Error!Response {
    if (!try store.delete(id)) return notFound(arena);
    return .{ .status = .no_content };
}

fn listNotes(store: *Store, arena: Allocator, query: []const u8) Store.Error!Response {
    var failure: validate.Failure = undefined;
    const filter = validate.listFilter(arena, query, &failure) catch |err| switch (err) {
        error.Invalid => return errorResponse(arena, .bad_request, failure.message),
        error.OutOfMemory => return error.OutOfMemory,
    };
    const notes = try store.list(arena, filter);
    return json(arena, .ok, .{ .notes = notes });
}

fn stats(store: *Store, arena: Allocator) Store.Error!Response {
    const s = try store.stats(arena);
    var out: std.Io.Writer.Allocating = .init(arena);
    var w: Stringify = .{ .writer = &out.writer };
    writeStats(&w, s) catch return error.OutOfMemory;
    return .{ .status = .ok, .body = out.written() };
}

fn writeStats(w: *Stringify, s: Store.Stats) Stringify.Error!void {
    try w.beginObject();
    try w.objectField("notes");
    try w.write(s.notes);
    try w.objectField("tags");
    try w.beginObject();
    for (s.tags) |t| {
        try w.objectField(t.tag);
        try w.write(t.count);
    }
    try w.endObject();
    try w.endObject();
}

fn tags(store: *Store, arena: Allocator) Store.Error!Response {
    const s = try store.stats(arena);
    return json(arena, .ok, .{ .tags = s.tags });
}

fn json(arena: Allocator, status: Status, value: anytype) Allocator.Error!Response {
    const body = try Stringify.valueAlloc(arena, value, .{});
    return .{ .status = status, .body = body };
}

fn errorResponse(arena: Allocator, status: Status, message: []const u8) Allocator.Error!Response {
    return json(arena, status, .{ .@"error" = message });
}

fn notFound(arena: Allocator) Allocator.Error!Response {
    return errorResponse(arena, .not_found, "not found");
}

fn methodNotAllowed(arena: Allocator) Allocator.Error!Response {
    return errorResponse(arena, .method_not_allowed, "method not allowed");
}

const testing = std.testing;

const TestEnv = struct {
    store: Store,
    arena: std.heap.ArenaAllocator,

    fn init() !TestEnv {
        return .{
            .store = try Store.open(testing.io, ":memory:"),
            .arena = .init(testing.allocator),
        };
    }

    fn deinit(env: *TestEnv) void {
        env.store.close();
        env.arena.deinit();
    }

    fn call(env: *TestEnv, method: Method, target: []const u8, body: []const u8) !Response {
        return handle(&env.store, env.arena.allocator(), .{ .method = method, .target = target, .body = body });
    }
};

test "routing and status codes" {
    var env = try TestEnv.init();
    defer env.deinit();

    try testing.expectEqual(Status.ok, (try env.call(.GET, "/health", "")).status);
    try testing.expectEqual(Status.not_found, (try env.call(.GET, "/nope", "")).status);
    try testing.expectEqual(Status.method_not_allowed, (try env.call(.DELETE, "/notes", "")).status);
    try testing.expectEqual(Status.method_not_allowed, (try env.call(.POST, "/stats", "")).status);
    try testing.expectEqual(Status.not_found, (try env.call(.GET, "/notes/abc", "")).status);
    try testing.expectEqual(Status.not_found, (try env.call(.GET, "/notes/1", "")).status);

    const created = try env.call(.POST, "/notes", "{\"title\":\"a\",\"tags\":[\"y\",\"x\"]}");
    try testing.expectEqual(Status.created, created.status);
    try testing.expectEqualStrings("{\"id\":1,\"title\":\"a\",\"body\":\"\",\"tags\":[\"x\",\"y\"]}", created.body);

    try testing.expectEqual(Status.method_not_allowed, (try env.call(.POST, "/notes/1", "")).status);
    try testing.expectEqual(Status.bad_request, (try env.call(.GET, "/notes?limit=0", "")).status);

    const s = try env.call(.GET, "/stats", "");
    try testing.expectEqualStrings("{\"notes\":1,\"tags\":{\"x\":1,\"y\":1}}", s.body);

    const t = try env.call(.GET, "/tags", "");
    try testing.expectEqualStrings("{\"tags\":[{\"tag\":\"x\",\"count\":1},{\"tag\":\"y\",\"count\":1}]}", t.body);

    try testing.expectEqual(Status.no_content, (try env.call(.DELETE, "/notes/1", "")).status);
    try testing.expectEqualStrings("{\"notes\":[]}", (try env.call(.GET, "/notes", "")).body);
}
