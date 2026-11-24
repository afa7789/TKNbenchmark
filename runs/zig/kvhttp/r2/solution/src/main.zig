//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port>)

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

pub const std_options: std.Options = .{
    .log_level = .warn,
};

/// Largest accepted value, in bytes.
const max_value_len = 1024 * 1024;
/// Largest accepted key, in bytes.
const max_key_len = 64;
/// Size of the per-connection receive buffer; bounds the request head size.
const recv_buffer_len = 16 * 1024;
const send_buffer_len = 4 * 1024;

const Context = struct {
    io: Io,
    gpa: Allocator,
    store: Store,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const port_arg = args.next() orelse fatal("usage: app <port>", .{});
    const port = std.fmt.parseInt(u16, port_arg, 10) catch
        fatal("invalid port: {s}", .{port_arg});

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }) catch |err|
        fatal("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer server.deinit(io);

    var ctx: Context = .{ .io = io, .gpa = gpa, .store = .init(gpa) };
    defer ctx.store.deinit();

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted, error.ProtocolFailure => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                log.warn("accept: {t}", .{err});
                io.sleep(.fromMilliseconds(10), .awake) catch return;
                continue;
            },
            else => return err,
        };
        group.concurrent(io, serveConnection, .{ &ctx, stream }) catch {
            // No thread available: serve inline rather than dropping the client.
            serveConnection(&ctx, stream);
        };
    }
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}

fn serveConnection(ctx: *Context, stream: net.Stream) void {
    const io = ctx.io;
    defer stream.close(io);

    var recv_buffer: [recv_buffer_len]u8 = undefined;
    var send_buffer: [send_buffer_len]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    while (true) {
        const keep_alive = handleRequest(ctx, &server) catch |err| {
            log.debug("connection error: {t}", .{err});
            return;
        };
        if (!keep_alive) return;
    }
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

/// The parts of a request head this server cares about. `target` points into
/// the connection's receive buffer and is invalidated once the body is read.
const RequestHead = struct {
    /// Null when the method is syntactically valid but unknown to us.
    method: ?http.Method,
    target: []const u8,
    content_length: ?u64,
    transfer_encoding: http.TransferEncoding,
    keep_alive: bool,
};

fn parseHead(bytes: []const u8) error{HttpHeadersInvalid}!RequestHead {
    if (http.Server.Request.Head.parse(bytes)) |head| {
        return .{
            .method = head.method,
            .target = head.target,
            .content_length = head.content_length,
            .transfer_encoding = head.transfer_encoding,
            .keep_alive = head.keep_alive,
        };
    } else |err| switch (err) {
        error.UnknownHttpMethod => return parseHeadUnknownMethod(bytes),
        else => return error.HttpHeadersInvalid,
    }
}

/// Minimal parse for requests whose method std.http does not know, so they can
/// still be routed (and answered with 405 / 404 / 400) and their body drained.
fn parseHeadUnknownMethod(bytes: []const u8) error{HttpHeadersInvalid}!RequestHead {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const request_line = std.mem.trimEnd(u8, lines.first(), "\r");
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.HttpHeadersInvalid;
    const target = parts.next() orelse return error.HttpHeadersInvalid;
    const version = parts.next() orelse return error.HttpHeadersInvalid;
    if (method.len == 0 or target.len == 0 or parts.next() != null or
        !std.mem.startsWith(u8, version, "HTTP/1."))
        return error.HttpHeadersInvalid;

    var head: RequestHead = .{
        .method = null,
        .target = target,
        .content_length = null,
        .transfer_encoding = .none,
        // Unknown territory: do not try to reuse the connection.
        .keep_alive = false,
    };
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) break;
        const colon = std.mem.findScalar(u8, line, ':') orelse return error.HttpHeadersInvalid;
        const name = line[0..colon];
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            head.content_length = std.fmt.parseInt(u64, value, 10) catch
                return error.HttpHeadersInvalid;
        } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            if (!std.ascii.eqlIgnoreCase(value, "chunked")) return error.HttpHeadersInvalid;
            head.transfer_encoding = .chunked;
        }
    }
    return head;
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

const Key = struct {
    buf: [max_key_len]u8,
    len: u8,

    fn slice(k: *const Key) []const u8 {
        return k.buf[0..k.len];
    }
};

const Route = union(enum) {
    health,
    list,
    item: Key,
    bad_key,
    not_found,
};

fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

fn route(target: []const u8) Route {
    if (std.mem.eql(u8, target, "/health")) return .health;
    if (std.mem.eql(u8, target, "/kv")) return .list;
    const prefix = "/kv/";
    if (std.mem.startsWith(u8, target, prefix)) {
        const key = target[prefix.len..];
        if (!isValidKey(key)) return .bad_key;
        var k: Key = .{ .buf = undefined, .len = @intCast(key.len) };
        @memcpy(k.buf[0..key.len], key);
        return .{ .item = k };
    }
    return .not_found;
}

// ---------------------------------------------------------------------------
// Request handling
// ---------------------------------------------------------------------------

const Response = struct {
    status: http.Status,
    body: []const u8 = "",
    content_type: ?[]const u8 = null,
    allow: ?[]const u8 = null,
    /// Heap-allocated body to free after sending.
    owned: ?[]u8 = null,
};

/// Handles one request on the connection. Returns whether the connection may
/// be reused for another request.
fn handleRequest(ctx: *Context, server: *http.Server) !bool {
    const out = server.out;

    const head_bytes = server.reader.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return false,
        error.HttpHeadersOversize => {
            try writeResponse(out, .{ .status = .request_header_fields_too_large }, false);
            return false;
        },
        else => |e| return e,
    };
    const head = parseHead(head_bytes) catch {
        try writeResponse(out, .{ .status = .bad_request }, false);
        return false;
    };

    // Resolve the route before touching the body: `head.target` lives in the
    // receive buffer, which reading the body may overwrite.
    const method = head.method;
    const r = route(head.target);

    const has_body = head.transfer_encoding == .chunked or (head.content_length orelse 0) > 0;
    const body_reader: *Io.Reader = if (has_body)
        server.reader.bodyReader(&.{}, head.transfer_encoding, head.content_length)
    else blk: {
        server.reader.state = .ready;
        break :blk .ending;
    };

    var keep_alive = head.keep_alive;
    const response: Response = switch (r) {
        .not_found => .{ .status = .not_found },
        .bad_key => .{ .status = .bad_request },
        .health => if (method == .GET)
            .{ .status = .ok, .body = "ok", .content_type = "text/plain" }
        else
            .{ .status = .method_not_allowed, .allow = "GET" },
        .list => if (method == .GET) list: {
            const json = try ctx.store.keysJson(ctx.io, ctx.gpa);
            break :list .{ .status = .ok, .body = json, .owned = json, .content_type = "application/json" };
        } else .{ .status = .method_not_allowed, .allow = "GET" },
        .item => |*key| if (method) |m| switch (m) {
            .GET => get: {
                const value = try ctx.store.getCopy(ctx.io, ctx.gpa, key.slice()) orelse
                    break :get .{ .status = .not_found };
                break :get .{
                    .status = .ok,
                    .body = value,
                    .owned = value,
                    .content_type = "application/octet-stream",
                };
            },
            .PUT => put: {
                const value = readValue(ctx.gpa, body_reader, head.content_length) catch |err| switch (err) {
                    error.StreamTooLong => {
                        keep_alive = false;
                        break :put .{ .status = .payload_too_large };
                    },
                    else => |e| return e,
                };
                errdefer ctx.gpa.free(value);
                const result = try ctx.store.put(ctx.io, key.slice(), value);
                break :put .{ .status = switch (result) {
                    .created => .created,
                    .replaced => .ok,
                } };
            },
            .DELETE => .{ .status = if (ctx.store.remove(ctx.io, key.slice())) .no_content else .not_found },
            else => .{ .status = .method_not_allowed, .allow = "GET, PUT, DELETE" },
        } else .{ .status = .method_not_allowed, .allow = "GET, PUT, DELETE" },
    };
    defer if (response.owned) |owned| ctx.gpa.free(owned);

    // Consume whatever is left of the request body so the client never sees
    // a reset caused by unread data, and so the connection can be reused.
    if (has_body) {
        _ = body_reader.discardRemaining() catch |err|
            return server.reader.body_err orelse err;
    }

    try writeResponse(out, response, keep_alive);
    return keep_alive;
}

/// Reads a request body of at most `max_value_len` bytes into a buffer owned
/// by the caller.
fn readValue(gpa: Allocator, body: *Io.Reader, content_length: ?u64) ![]u8 {
    if (content_length) |len| {
        if (len > max_value_len) return error.StreamTooLong;
        const value = try gpa.alloc(u8, @intCast(len));
        errdefer gpa.free(value);
        try body.readSliceAll(value);
        return value;
    }
    return body.allocRemaining(gpa, .limited(max_value_len));
}

fn writeResponse(out: *Io.Writer, response: Response, keep_alive: bool) Io.Writer.Error!void {
    const status = response.status;
    try out.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase() orelse "" });
    try out.print("content-length: {d}\r\n", .{response.body.len});
    if (response.content_type) |ct| try out.print("content-type: {s}\r\n", .{ct});
    if (response.allow) |allow| try out.print("allow: {s}\r\n", .{allow});
    if (!keep_alive) try out.writeAll("connection: close\r\n");
    try out.writeAll("\r\n");
    try out.writeAll(response.body);
    try out.flush();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "route" {
    try std.testing.expectEqual(.health, route("/health"));
    try std.testing.expectEqual(.list, route("/kv"));
    try std.testing.expectEqual(.bad_key, route("/kv/"));
    try std.testing.expectEqual(.bad_key, route("/kv/a/b"));
    try std.testing.expectEqual(.bad_key, route("/kv/bad.key"));
    try std.testing.expectEqual(.bad_key, route("/kv/" ++ "a" ** 65));
    try std.testing.expectEqualStrings("a" ** 64, route("/kv/" ++ "a" ** 64).item.slice());
    try std.testing.expectEqualStrings("A-z_9", route("/kv/A-z_9").item.slice());
    try std.testing.expectEqual(.not_found, route("/"));
    try std.testing.expectEqual(.not_found, route("/kvx"));
    try std.testing.expectEqual(.not_found, route("/health/"));
}

test "parse head with unknown method" {
    const head = try parseHead("BREW /kv/a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\n");
    try std.testing.expectEqual(null, head.method);
    try std.testing.expectEqualStrings("/kv/a", head.target);
    try std.testing.expectEqual(5, head.content_length);
}

test {
    _ = Store;
}
