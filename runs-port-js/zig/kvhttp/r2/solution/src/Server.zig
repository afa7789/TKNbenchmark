//! HTTP/1.1 front end for `Store`.
//!
//! Each connection is served by `serveConnection`, which handles requests in a
//! loop while the client keeps the connection alive.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");

const Server = @This();

io: Io,
gpa: Allocator,
store: *Store,

pub const max_value_len = 1024 * 1024;
pub const max_head_len = 64 * 1024;
pub const max_key_len = 64;
/// Upper bound on request bytes read and discarded before closing a
/// connection whose request body was not consumed. Closing a socket with
/// unread input makes the kernel send a reset, which can destroy the response
/// before the client reads it.
const max_linger_len = 4 * max_value_len;
const send_buffer_len = 16 * 1024;

pub fn serveConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    const recv_buffer = server.gpa.alloc(u8, max_head_len) catch return;
    defer server.gpa.free(recv_buffer);
    var send_buffer: [send_buffer_len]u8 = undefined;

    var stream_reader = stream.reader(io, recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);

    var conn: Connection = .{
        .server = server,
        .in = .{
            .in = &stream_reader.interface,
            .state = .ready,
            .interface = undefined,
            .max_head_len = max_head_len,
        },
        .out = &stream_writer.interface,
    };

    while (conn.serveRequest()) {}

    if (conn.body_pending) {
        // Lingering close: let the peer see our FIN, then swallow whatever it
        // is still sending so that closing does not reset the connection.
        stream.shutdown(io, .send) catch return;
        var drained: usize = 0;
        while (drained < max_linger_len) {
            drained += stream_reader.interface.discard(.limited(max_linger_len - drained)) catch break;
        }
    }
}

const Connection = struct {
    server: *Server,
    in: http.Reader,
    out: *Io.Writer,
    /// The current request declared a body that has not been consumed yet.
    body_pending: bool = false,

    /// Statuses produced while handling a request. They are answered with an
    /// empty body and the connection is closed afterwards.
    const RequestError = error{
        BadRequest,
        NotFound,
        MethodNotAllowed,
        PayloadTooLarge,
    };

    const HandleError = RequestError || Allocator.Error || error{ ReadFailed, WriteFailed, EndOfStream };

    /// Serves one request. Returns whether the connection may be reused.
    fn serveRequest(conn: *Connection) bool {
        const head_bytes = conn.in.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing, error.HttpRequestTruncated, error.ReadFailed => return false,
            error.HttpHeadersOversize => {
                conn.sendError(.request_header_fields_too_large, null);
                return false;
            },
        };
        const head = Head.parse(head_bytes) catch {
            conn.sendError(.bad_request, null);
            return false;
        };
        conn.body_pending = head.hasBody();

        return conn.handle(&head) catch |err| {
            const status: http.Status = switch (err) {
                error.BadRequest => .bad_request,
                error.NotFound => .not_found,
                error.MethodNotAllowed => .method_not_allowed,
                error.PayloadTooLarge => .payload_too_large,
                error.OutOfMemory => .internal_server_error,
                error.ReadFailed, error.WriteFailed, error.EndOfStream => return false,
            };
            conn.sendError(status, &head);
            return false;
        };
    }

    fn handle(conn: *Connection, head: *const Head) HandleError!bool {
        const io = conn.server.io;
        const store = conn.server.store;

        switch (try Route.parse(head.target)) {
            .health => {
                if (head.method != .GET) return error.MethodNotAllowed;
                return conn.respond(head, .{
                    .status = .ok,
                    .content_type = "text/plain; charset=utf-8",
                    .body = "ok",
                });
            },
            .list => {
                if (head.method != .GET) return error.MethodNotAllowed;
                var json: Io.Writer.Allocating = .init(conn.server.gpa);
                defer json.deinit();
                store.writeKeysJson(io, conn.server.gpa, &json.writer) catch return error.OutOfMemory;
                return conn.respond(head, .{
                    .status = .ok,
                    .content_type = "application/json",
                    .body = json.written(),
                });
            },
            .item => |key| switch (head.method) {
                .GET => {
                    const value = try store.get(io, conn.server.gpa, key) orelse return error.NotFound;
                    defer conn.server.gpa.free(value);
                    return conn.respond(head, .{
                        .status = .ok,
                        .content_type = "application/octet-stream",
                        .body = value,
                    });
                },
                .PUT => {
                    // `key` points into the receive buffer, which reading the
                    // body may overwrite.
                    var key_buffer: [max_key_len]u8 = undefined;
                    const owned_key = key_buffer[0..key.len];
                    @memcpy(owned_key, key);

                    const value = try conn.readBody(head);
                    errdefer conn.server.gpa.free(value);
                    const status: http.Status = switch (try store.put(io, owned_key, value)) {
                        .created => .created,
                        .replaced => .ok,
                    };
                    return conn.respond(head, .{ .status = status });
                },
                .DELETE => {
                    if (!store.remove(io, key)) return error.NotFound;
                    return conn.respond(head, .{ .status = .no_content });
                },
                .HEAD, .other => return error.MethodNotAllowed,
            },
        }
    }

    /// Reads the whole request body into memory owned by the caller.
    fn readBody(conn: *Connection, head: *const Head) HandleError![]u8 {
        const gpa = conn.server.gpa;
        const value = if (head.chunked) value: {
            try conn.sendContinue(head);
            const body = conn.in.bodyReader(&.{}, .chunked, null);
            var list: std.ArrayList(u8) = .empty;
            errdefer list.deinit(gpa);
            body.appendRemaining(gpa, &list, .limited(max_value_len + 1)) catch |err| switch (err) {
                error.StreamTooLong => return error.PayloadTooLarge,
                error.OutOfMemory => return error.OutOfMemory,
                error.ReadFailed => return if (conn.in.body_err != null) error.BadRequest else error.ReadFailed,
            };
            break :value try list.toOwnedSlice(gpa);
        } else value: {
            const len = head.content_length orelse 0;
            if (len > max_value_len) return error.PayloadTooLarge;
            try conn.sendContinue(head);
            break :value try conn.in.in.readAlloc(gpa, @intCast(len));
        };
        conn.body_pending = false;
        return value;
    }

    /// Consumes an unused request body so the next request can be read.
    fn discardBody(conn: *Connection, head: *const Head) error{ ReadFailed, EndOfStream }!void {
        if (!conn.body_pending) return;
        if (head.chunked) {
            _ = conn.in.bodyReader(&.{}, .chunked, null).discardRemaining() catch |err| switch (err) {
                error.ReadFailed => return error.ReadFailed,
            };
        } else {
            try conn.in.in.discardAll64(head.content_length orelse 0);
        }
        conn.body_pending = false;
    }

    fn sendContinue(conn: *Connection, head: *const Head) error{WriteFailed}!void {
        if (!head.expect_continue) return;
        try conn.out.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
        try conn.out.flush();
    }

    const Response = struct {
        status: http.Status,
        content_type: ?[]const u8 = null,
        body: []const u8 = "",
    };

    /// Sends a successful response. Returns whether the connection may be reused.
    fn respond(conn: *Connection, head: *const Head, response: Response) HandleError!bool {
        // An unread body must be skipped before the next request can be
        // parsed. Do not do so if the client is waiting for permission to
        // send it; closing is cheaper.
        const keep_alive = head.keep_alive and !(conn.body_pending and head.expect_continue);
        if (keep_alive) try conn.discardBody(head);

        try conn.writeResponse(head, response, keep_alive);
        return keep_alive;
    }

    /// Best-effort error response; the connection is closed afterwards.
    fn sendError(conn: *Connection, status: http.Status, head: ?*const Head) void {
        conn.writeResponse(head, .{ .status = status }, false) catch {};
    }

    fn writeResponse(conn: *Connection, head: ?*const Head, response: Response, keep_alive: bool) error{WriteFailed}!void {
        const out = conn.out;
        const version: http.Version = if (head) |h| h.version else .@"HTTP/1.1";

        try out.print("HTTP/1.1 {d} {s}\r\n", .{
            @intFromEnum(response.status), response.status.phrase() orelse "",
        });
        if (response.content_type) |content_type| {
            try out.print("Content-Type: {s}\r\n", .{content_type});
        }
        const has_body = response.status != .no_content and response.status != .not_modified;
        if (has_body) try out.print("Content-Length: {d}\r\n", .{response.body.len});
        switch (version) {
            .@"HTTP/1.1" => if (!keep_alive) try out.writeAll("Connection: close\r\n"),
            .@"HTTP/1.0" => if (keep_alive) try out.writeAll("Connection: keep-alive\r\n"),
        }
        try out.writeAll("\r\n");

        const is_head = if (head) |h| h.method == .HEAD else false;
        if (has_body and !is_head) try out.writeAll(response.body);
        try out.flush();
    }
};

const Route = union(enum) {
    health,
    list,
    item: []const u8,

    const prefix = "/kv/";

    fn parse(target: []const u8) error{ NotFound, BadRequest }!Route {
        if (std.mem.eql(u8, target, "/health")) return .health;
        if (std.mem.eql(u8, target, "/kv")) return .list;
        if (std.mem.startsWith(u8, target, prefix)) {
            const key = target[prefix.len..];
            if (!isValidKey(key)) return error.BadRequest;
            return .{ .item = key };
        }
        return error.NotFound;
    }
};

/// A key matches `[A-Za-z0-9_-]{1,64}`.
pub fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

/// The parts of a request head this server cares about. Slices point into the
/// connection's receive buffer.
const Head = struct {
    method: Method,
    target: []const u8,
    version: http.Version,
    content_length: ?u64 = null,
    chunked: bool = false,
    keep_alive: bool,
    expect_continue: bool = false,

    const Method = enum { GET, HEAD, PUT, DELETE, other };

    fn hasBody(head: *const Head) bool {
        return head.chunked or (head.content_length orelse 0) > 0;
    }

    fn parse(bytes: []const u8) error{Invalid}!Head {
        var lines = std.mem.splitScalar(u8, bytes, '\n');

        const request_line = trimCr(lines.first());
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.first();
        const target = parts.next() orelse return error.Invalid;
        const version_text = parts.next() orelse return error.Invalid;
        if (parts.next() != null) return error.Invalid;
        if (!isToken(method) or target.len == 0) return error.Invalid;
        for (target) |c| if (c <= ' ' or c == 0x7f) return error.Invalid;

        const version: http.Version = if (std.mem.eql(u8, version_text, "HTTP/1.1"))
            .@"HTTP/1.1"
        else if (std.mem.eql(u8, version_text, "HTTP/1.0"))
            .@"HTTP/1.0"
        else
            return error.Invalid;

        var head: Head = .{
            .method = std.meta.stringToEnum(Method, method) orelse .other,
            .target = target,
            .version = version,
            .keep_alive = version == .@"HTTP/1.1",
        };
        var transfer_encoding: ?[]const u8 = null;

        while (lines.next()) |raw_line| {
            const line = trimCr(raw_line);
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.Invalid;
            const name = line[0..colon];
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (!isToken(name)) return error.Invalid;
            for (value) |c| if ((c < ' ' and c != '\t') or c == 0x7f) return error.Invalid;

            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                const len = std.fmt.parseUnsigned(u64, value, 10) catch return error.Invalid;
                if (head.content_length) |prev| if (prev != len) return error.Invalid;
                head.content_length = len;
            } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                if (transfer_encoding != null) return error.Invalid;
                transfer_encoding = value;
            } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
                var options = std.mem.tokenizeAny(u8, value, ", \t");
                while (options.next()) |option| {
                    if (std.ascii.eqlIgnoreCase(option, "close")) {
                        head.keep_alive = false;
                    } else if (std.ascii.eqlIgnoreCase(option, "keep-alive")) {
                        head.keep_alive = true;
                    }
                }
            } else if (std.ascii.eqlIgnoreCase(name, "expect")) {
                if (!std.ascii.eqlIgnoreCase(value, "100-continue")) return error.Invalid;
                head.expect_continue = true;
            }
        }

        if (transfer_encoding) |te| {
            // Only plain chunked framing is supported, and it must not be
            // combined with Content-Length (request smuggling vector).
            if (!std.ascii.eqlIgnoreCase(te, "chunked") or head.content_length != null) return error.Invalid;
            head.chunked = true;
        }
        return head;
    }

    fn trimCr(line: []const u8) []const u8 {
        return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
    }

    fn isToken(s: []const u8) bool {
        if (s.len == 0) return false;
        for (s) |c| switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9' => {},
            '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
            else => return false,
        };
        return true;
    }
};

test isValidKey {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("A-z_09"));
    try std.testing.expect(isValidKey("k" ** 64));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("k" ** 65));
    try std.testing.expect(!isValidKey("a/b"));
    try std.testing.expect(!isValidKey("bad.key"));
    try std.testing.expect(!isValidKey("a%20b"));
}

test "Route.parse" {
    try std.testing.expectEqual(Route.health, try Route.parse("/health"));
    try std.testing.expectEqual(Route.list, try Route.parse("/kv"));
    try std.testing.expectEqualStrings("abc", (try Route.parse("/kv/abc")).item);
    try std.testing.expectError(error.BadRequest, Route.parse("/kv/"));
    try std.testing.expectError(error.BadRequest, Route.parse("/kv/a/b"));
    try std.testing.expectError(error.NotFound, Route.parse("/kv2"));
    try std.testing.expectError(error.NotFound, Route.parse("/health/"));
    try std.testing.expectError(error.NotFound, Route.parse("/"));
}

test "Head.parse" {
    const head = try Head.parse("PUT /kv/a HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\nConnection: close\r\n\r\n");
    try std.testing.expectEqual(Head.Method.PUT, head.method);
    try std.testing.expectEqualStrings("/kv/a", head.target);
    try std.testing.expectEqual(5, head.content_length.?);
    try std.testing.expect(!head.keep_alive);
    try std.testing.expect(head.hasBody());

    const other = try Head.parse("PROPFIND /health HTTP/1.0\r\n\r\n");
    try std.testing.expectEqual(Head.Method.other, other.method);
    try std.testing.expect(!other.keep_alive);

    try std.testing.expectError(error.Invalid, Head.parse("GET /x HTTP/2.0\r\n\r\n"));
    try std.testing.expectError(error.Invalid, Head.parse("GET /x HTTP/1.1\r\nContent-Length: x\r\n\r\n"));
    try std.testing.expectError(error.Invalid, Head.parse("GET /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\n\r\n"));
}
