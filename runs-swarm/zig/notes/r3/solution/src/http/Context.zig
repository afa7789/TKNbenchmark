//! Everything a handler needs to serve one request: the parsed request
//! line, path parameters, a per-request arena, the database, and helpers to
//! read the body and send the response.

const Context = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;
const Store = @import("../db/Store.zig");
const query_string = @import("query.zig");

/// Request bodies larger than this are rejected with 413.
pub const max_body_len = 1 << 20;

/// Errors a handler may return. `error.PayloadTooLarge` is answered with
/// 413; read and write failures drop the connection; anything else is
/// logged and answered with 500 if no response was sent yet.
pub const Error = Allocator.Error || error{
    Sqlite,
    PayloadTooLarge,
    ReadFailed,
    WriteFailed,
    HttpExpectationFailed,
};

pub const Param = struct {
    name: []const u8,
    value: []const u8,
};

/// Freed when the request is done.
arena: Allocator,
store: *Store,
request: *http.Server.Request,
method: http.Method,
/// The request path, without the query string. Not decoded.
path: []const u8,
/// The raw query string, without the `?`. Empty if there is none.
query: []const u8,
/// Values of the `{name}` segments of the matched route pattern.
params: []const Param = &.{},
responded: bool = false,

/// Initializes a context for `request`. Copies the request target into
/// `arena`, because reading the body invalidates the request head.
pub fn init(arena: Allocator, store: *Store, request: *http.Server.Request) Allocator.Error!Context {
    const target = try arena.dupe(u8, request.head.target);
    const query_start = std.mem.indexOfScalar(u8, target, '?');
    return .{
        .arena = arena,
        .store = store,
        .request = request,
        .method = request.head.method,
        .path = target[0 .. query_start orelse target.len],
        .query = if (query_start) |i| target[i + 1 ..] else "",
    };
}

/// The value of the path parameter `name`. Asserts the matched route
/// pattern declares it.
pub fn param(ctx: *const Context, name: []const u8) []const u8 {
    for (ctx.params) |p| {
        if (std.mem.eql(u8, p.name, name)) return p.value;
    }
    unreachable;
}

/// The decoded value of the query parameter `name`, or null if absent.
pub fn queryParam(ctx: *const Context, name: []const u8) Allocator.Error!?[]const u8 {
    return query_string.get(ctx.arena, ctx.query, name);
}

/// Reads the whole request body into the arena.
pub fn readBody(ctx: *Context) Error![]const u8 {
    var buf: [4096]u8 = undefined;
    const reader = try ctx.request.readerExpectContinue(&buf);
    return reader.allocRemaining(ctx.arena, .limited(max_body_len)) catch |err| switch (err) {
        error.StreamTooLong => error.PayloadTooLarge,
        error.ReadFailed, error.OutOfMemory => |e| e,
    };
}

/// Sends `value` serialized as JSON.
pub fn sendJson(ctx: *Context, status: http.Status, value: anytype) Error!void {
    const body = try std.json.Stringify.valueAlloc(ctx.arena, value, .{});
    try ctx.send(status, "application/json", body);
}

/// Sends `{"error": message}`.
pub fn sendError(ctx: *Context, status: http.Status, message: []const u8) Error!void {
    try ctx.sendJson(status, .{ .@"error" = message });
}

/// Sends a response without a body, such as 204 No Content.
pub fn sendEmpty(ctx: *Context, status: http.Status) Error!void {
    try ctx.respond(status, "", &.{});
}

pub fn send(ctx: *Context, status: http.Status, content_type: []const u8, body: []const u8) Error!void {
    try ctx.respond(status, body, &.{.{ .name = "content-type", .value = content_type }});
}

/// Sends a response with arbitrary headers. Asserts no response was sent yet.
pub fn respond(ctx: *Context, status: http.Status, body: []const u8, headers: []const http.Header) Error!void {
    std.debug.assert(!ctx.responded);
    ctx.responded = true;
    try ctx.request.respond(body, .{ .status = status, .extra_headers = headers });
}
