//! HTTP/1.1 front end for the key-value store: request routing and the
//! per-connection handler. Each connection serves exactly one request.

const std = @import("std");
const Io = std.Io;
const http = std.http;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.kvhttp);

const Store = @import("Store.zig");

pub const max_value_bytes = 1024 * 1024;
pub const max_key_len = 64;

/// Upper bound on request bytes read (and thrown away) when a request body is
/// not used, so the connection can be closed without the kernel resetting it.
const max_drain_bytes = 8 * max_value_bytes;
/// Must hold the entire request head.
const read_buffer_len = 16 * 1024;
const write_buffer_len = 16 * 1024;

pub const Route = union(enum) {
    health,
    list,
    item: []const u8,
    invalid_key,
    not_found,

    pub fn parse(target: []const u8) Route {
        const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];
        if (std.mem.eql(u8, path, "/health")) return .health;
        if (std.mem.eql(u8, path, "/kv")) return .list;
        if (std.mem.startsWith(u8, path, "/kv/")) {
            const key = path["/kv/".len..];
            return if (isValidKey(key)) .{ .item = key } else .invalid_key;
        }
        return .not_found;
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

pub const Context = struct {
    io: Io,
    gpa: Allocator,
    store: *Store,
};

/// Serves one request on `stream`, then closes it.
pub fn handleConnection(ctx: *const Context, stream: Io.net.Stream) Io.Cancelable!void {
    defer stream.close(ctx.io);

    var read_buffer: [read_buffer_len]u8 = undefined;
    var write_buffer: [write_buffer_len]u8 = undefined;
    var conn_reader = stream.reader(ctx.io, &read_buffer);
    var conn_writer = stream.writer(ctx.io, &write_buffer);
    var server: http.Server = .init(&conn_reader.interface, &conn_writer.interface);

    serve(ctx, &server) catch |err| switch (err) {
        // The peer went away or sent garbage; nothing useful left to do.
        error.ReadFailed, error.WriteFailed => {},
        else => log.warn("connection error: {t}", .{err}),
    };
}

fn serve(ctx: *const Context, server: *http.Server) !void {
    var request = server.receiveHead() catch |err| {
        const status: http.Status = switch (err) {
            error.HttpConnectionClosing, error.HttpRequestTruncated, error.ReadFailed => return,
            error.HttpHeadersOversize => .request_header_fields_too_large,
            error.HttpHeadersInvalid => .bad_request,
        };
        return writeRawError(server.out, status);
    };

    var exchange: Exchange = .{ .ctx = ctx, .request = &request };
    try exchange.run();
}

/// Responds without a parsed request, for requests too malformed to route.
fn writeRawError(out: *Io.Writer, status: http.Status) Io.Writer.Error!void {
    const phrase = status.phrase() orelse "Error";
    try out.print("HTTP/1.1 {d} {s}\r\nconnection: close\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: {d}\r\n\r\n{s}", .{
        @intFromEnum(status), phrase, phrase.len, phrase,
    });
    try out.flush();
}

const Exchange = struct {
    ctx: *const Context,
    request: *http.Server.Request,
    body_consumed: bool = false,

    const allow_read_only = "GET";
    const allow_item = "GET, PUT, DELETE";

    fn run(ex: *Exchange) !void {
        const method = ex.request.head.method;
        switch (Route.parse(ex.request.head.target)) {
            .health => {
                if (method != .GET) return ex.methodNotAllowed(allow_read_only);
                return ex.respond(.ok, "ok", "text/plain; charset=utf-8");
            },
            .list => {
                if (method != .GET) return ex.methodNotAllowed(allow_read_only);
                const json = try ex.ctx.store.keysJson(ex.ctx.io, ex.ctx.gpa);
                defer ex.ctx.gpa.free(json);
                return ex.respond(.ok, json, "application/json");
            },
            .item => |target_key| {
                // The head buffer is reused once the body is read; keep a copy.
                var key_buf: [max_key_len]u8 = undefined;
                const key = key_buf[0..target_key.len];
                @memcpy(key, target_key);

                switch (method) {
                    .GET => {
                        const value = try ex.ctx.store.getCopy(ex.ctx.io, ex.ctx.gpa, key) orelse
                            return ex.respondError(.not_found);
                        defer ex.ctx.gpa.free(value);
                        return ex.respond(.ok, value, "application/octet-stream");
                    },
                    .PUT => {
                        const value = ex.readBody() catch |err| switch (err) {
                            error.StreamTooLong => return ex.respondError(.payload_too_large),
                            error.HttpExpectationFailed => return ex.respondError(.expectation_failed),
                            else => |e| return e,
                        };
                        const status: http.Status = switch (try ex.ctx.store.put(ex.ctx.io, key, value)) {
                            .created => .created,
                            .replaced => .ok,
                        };
                        return ex.respond(status, "", null);
                    },
                    .DELETE => {
                        if (!ex.ctx.store.remove(ex.ctx.io, key)) return ex.respondError(.not_found);
                        return ex.respond(.no_content, "", null);
                    },
                    else => return ex.methodNotAllowed(allow_item),
                }
            },
            .invalid_key => return ex.respondError(.bad_request),
            .not_found => return ex.respondError(.not_found),
        }
    }

    const ReadBodyError = Allocator.Error || Io.Reader.ShortError || http.Server.Request.ExpectContinueError || error{StreamTooLong};

    /// Reads the whole request body. The result is owned by the caller.
    fn readBody(ex: *Exchange) ReadBodyError![]u8 {
        const gpa = ex.ctx.gpa;
        const declared = ex.request.head.content_length;
        if (declared) |len| if (len > max_value_bytes) return error.StreamTooLong;

        const body = try ex.request.readerExpectContinue(&.{});
        ex.body_consumed = true;

        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(gpa);
        if (declared) |len| try list.ensureTotalCapacityPrecise(gpa, @intCast(len));
        // `appendRemaining` fails once the limit is reached, so allow one
        // extra byte to accept bodies of exactly `max_value_bytes`.
        try body.appendRemaining(gpa, &list, .limited(max_value_bytes + 1));
        return list.toOwnedSlice(gpa);
    }

    fn methodNotAllowed(ex: *Exchange, allow: []const u8) !void {
        return ex.send(.method_not_allowed, phraseOf(.method_not_allowed), .{
            .content_type = "text/plain; charset=utf-8",
            .allow = allow,
        });
    }

    fn respondError(ex: *Exchange, status: http.Status) !void {
        return ex.respond(status, phraseOf(status), "text/plain; charset=utf-8");
    }

    fn respond(ex: *Exchange, status: http.Status, body: []const u8, content_type: ?[]const u8) !void {
        return ex.send(status, body, .{ .content_type = if (body.len > 0) content_type else null });
    }

    const Extra = struct {
        content_type: ?[]const u8 = null,
        allow: ?[]const u8 = null,
    };

    fn send(ex: *Exchange, status: http.Status, body: []const u8, extra: Extra) !void {
        if (!ex.body_consumed) {
            // Never invite a body we are not going to read.
            ex.request.head.expect = null;
        }

        var headers_buf: [2]http.Header = undefined;
        var headers: std.ArrayList(http.Header) = .initBuffer(&headers_buf);
        if (extra.content_type) |v| headers.appendAssumeCapacity(.{ .name = "content-type", .value = v });
        if (extra.allow) |v| headers.appendAssumeCapacity(.{ .name = "allow", .value = v });

        // A 204 response must not carry a Content-Length; omitting it makes
        // the connection close delimit the (empty) body instead.
        const transfer_encoding: ?http.TransferEncoding = if (status == .no_content) .none else null;
        const content_length = ex.request.head.content_length;

        try ex.request.respond(body, .{
            .status = status,
            .keep_alive = false,
            .extra_headers = headers.items,
            .transfer_encoding = transfer_encoding,
        });

        if (!ex.body_consumed) {
            // Read what the client is still sending so that closing the
            // socket does not reset the connection before it reads the reply.
            if (content_length) |len| {
                _ = ex.request.server.reader.in.discard(.limited(@min(len, max_drain_bytes))) catch {};
            }
        }
    }
};

fn phraseOf(status: http.Status) []const u8 {
    return status.phrase() orelse "Error";
}

test "route parsing" {
    const t = std.testing;
    try t.expectEqual(.health, Route.parse("/health"));
    try t.expectEqual(.list, Route.parse("/kv"));
    try t.expectEqual(.list, Route.parse("/kv?x=1"));
    try t.expectEqualStrings("a-B_9", Route.parse("/kv/a-B_9").item);
    try t.expectEqual(.invalid_key, Route.parse("/kv/"));
    try t.expectEqual(.invalid_key, Route.parse("/kv/a/b"));
    try t.expectEqual(.invalid_key, Route.parse("/kv/bad.key"));
    try t.expectEqual(.invalid_key, Route.parse("/kv/" ++ "x" ** 65));
    try t.expectEqualStrings("x" ** 64, Route.parse("/kv/" ++ "x" ** 64).item);
    try t.expectEqual(.not_found, Route.parse("/"));
    try t.expectEqual(.not_found, Route.parse("/kvx"));
    try t.expectEqual(.not_found, Route.parse("/health/"));
}
