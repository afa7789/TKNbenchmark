//! Types shared by the router and the endpoint handlers. Handlers see a
//! transport-independent `Request` and return a `Response`; `server.zig`
//! translates both to and from HTTP.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Pool = @import("db/Pool.zig");
const sqlite = @import("db/sqlite.zig");

pub const Method = std.http.Method;
pub const Status = std.http.Status;

pub const Request = struct {
    method: Method,
    /// The path without the query string, e.g. `/notes/3`.
    path: []const u8,
    /// The raw query string without the leading `?`; empty if there is none.
    query: []const u8 = "",
    /// The request body; empty for methods without one.
    body: []const u8 = "",

    /// Builds a request from an HTTP request target such as `/notes?tag=a`.
    pub fn init(method: Method, target: []const u8, body: []const u8) Request {
        const path, const query = if (std.mem.indexOfScalar(u8, target, '?')) |i|
            .{ target[0..i], target[i + 1 ..] }
        else
            .{ target, "" };
        return .{ .method = method, .path = path, .query = query, .body = body };
    }
};

test "Request.init splits the query string" {
    const with_query: Request = .init(.GET, "/notes?tag=a&q=b", "");
    try std.testing.expectEqualStrings("/notes", with_query.path);
    try std.testing.expectEqualStrings("tag=a&q=b", with_query.query);

    const without: Request = .init(.GET, "/notes", "");
    try std.testing.expectEqualStrings("/notes", without.path);
    try std.testing.expectEqualStrings("", without.query);
}

pub const Response = struct {
    status: Status,
    content_type: ContentType = .json,
    body: []const u8 = "",
    /// Value of the `Allow` header, set on 405 responses.
    allow: ?[]const u8 = null,

    pub const ContentType = enum {
        json,
        text,
        none,

        pub fn header(content_type: ContentType) ?[]const u8 {
            return switch (content_type) {
                .json => "application/json",
                .text => "text/plain; charset=utf-8",
                .none => null,
            };
        }
    };

    /// A JSON response with `value` serialized as the body.
    pub fn json(arena: Allocator, status: Status, value: anytype) Allocator.Error!Response {
        const body = try std.json.Stringify.valueAlloc(arena, value, .{});
        return .{ .status = status, .body = body };
    }

    pub fn text(status: Status, body: []const u8) Response {
        return .{ .status = status, .content_type = .text, .body = body };
    }

    /// A response without a body, e.g. 204.
    pub fn empty(status: Status) Response {
        return .{ .status = status, .content_type = .none };
    }

    /// An error response with the body `{"error": message}`.
    pub fn err(arena: Allocator, status: Status, message: []const u8) Allocator.Error!Response {
        return json(arena, status, .{ .@"error" = message });
    }

    pub fn notFound(arena: Allocator) Allocator.Error!Response {
        return err(arena, .not_found, "not found");
    }

    pub fn badRequest(arena: Allocator, message: []const u8) Allocator.Error!Response {
        return err(arena, .bad_request, message);
    }

    pub fn methodNotAllowed(arena: Allocator, allow: []const u8) Allocator.Error!Response {
        var response = try err(arena, .method_not_allowed, "method not allowed");
        response.allow = allow;
        return response;
    }
};

/// Per-request state handed to every handler.
pub const Context = struct {
    io: Io,
    /// Freed when the response has been sent; use it for all request-scoped
    /// allocations.
    arena: Allocator,
    pool: *Pool,

    /// Exclusive use of a database connection for the rest of the handler:
    ///
    ///     const conn = try ctx.acquireDb();
    ///     defer ctx.releaseDb(conn);
    ///
    /// Acquire at most one connection per request: holding one while waiting
    /// for another can deadlock when the pool is exhausted (tests use a pool
    /// of one).
    pub fn acquireDb(ctx: *const Context) Io.Cancelable!sqlite.Conn {
        return ctx.pool.acquire(ctx.io);
    }

    pub fn releaseDb(ctx: *const Context, conn: sqlite.Conn) void {
        ctx.pool.release(ctx.io, conn);
    }
};
