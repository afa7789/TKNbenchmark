//! HTTP/1.1 wire protocol for one client connection.
//!
//! Framing (head buffering, Content-Length and chunked bodies) is delegated to
//! `std.http.Reader`; the request line and headers are parsed here so that any
//! method token is accepted and routed (unknown methods must yield 405, not a
//! protocol error).

const Connection = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;
const Status = std.http.Status;

const Store = @import("Store.zig");
const handler = @import("handler.zig");

const log = std.log.scoped(.connection);

/// Largest accepted request body: 1 MiB values plus generous headroom.
pub const max_body_len = 8 * 1024 * 1024;
/// Largest accepted request head; also the size of the receive buffer.
const max_head_len = 16 * 1024;

store: *Store,
io: Io,
gpa: Allocator,
stream: net.Stream,

/// Serves requests on the connection until the client or protocol ends it,
/// then closes the stream.
pub fn serve(c: Connection) void {
    defer c.stream.close(c.io);

    var recv_buffer: [max_head_len]u8 = undefined;
    var send_buffer: [16 * 1024]u8 = undefined;
    var stream_reader = c.stream.reader(c.io, &recv_buffer);
    var stream_writer = c.stream.writer(c.io, &send_buffer);
    var http_reader: std.http.Reader = .{
        .in = &stream_reader.interface,
        .interface = undefined,
        .state = .ready,
        .max_head_len = recv_buffer.len,
    };
    var arena: std.heap.ArenaAllocator = .init(c.gpa);
    defer arena.deinit();

    while (true) {
        _ = arena.reset(.retain_capacity);
        const keep_alive = c.serveRequest(arena.allocator(), &http_reader, &stream_writer.interface) catch |err| {
            switch (err) {
                error.WriteFailed => log.debug("write failed: {t}", .{stream_writer.err.?}),
                error.ReadFailed => log.debug("read failed: {t}", .{stream_reader.err.?}),
                else => log.debug("connection error: {t}", .{err}),
            }
            return;
        };
        if (!keep_alive) return;
    }
}

const ServeError = Allocator.Error || Io.Writer.Error || error{ ReadFailed, HttpRequestTruncated };

/// Reads one request and writes its response. Returns whether the connection
/// may be reused for another request.
fn serveRequest(c: Connection, arena: Allocator, in: *std.http.Reader, out: *Io.Writer) ServeError!bool {
    in.state = .ready;
    const head_bytes = in.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return false,
        error.HttpHeadersOversize => return sendError(out, .request_header_fields_too_large),
        error.HttpRequestTruncated, error.ReadFailed => |e| return e,
    };

    // The head lives in the receive buffer, which reading the body reuses.
    const head = Head.parse(head_bytes) catch return sendError(out, .bad_request);
    const method = try arena.dupe(u8, head.method);
    const path = try arena.dupe(u8, head.path);

    if (head.content_length) |len| {
        if (len > max_body_len) return sendError(out, .payload_too_large);
    }
    if (head.expect_continue) {
        try out.writeAll("HTTP/1.1 100 Continue\r\n\r\n");
        try out.flush();
    }

    var transfer_buffer: [4096]u8 = undefined;
    const body: []const u8 = if (head.chunked or head.content_length != null) body: {
        const reader = in.bodyReader(&transfer_buffer, if (head.chunked) .chunked else .none, head.content_length);
        break :body reader.allocRemaining(arena, .limited(max_body_len)) catch |err| switch (err) {
            error.StreamTooLong => return sendError(out, .payload_too_large),
            error.OutOfMemory => |e| return e,
            error.ReadFailed => {
                if (in.body_err != null) return sendError(out, .bad_request);
                return error.ReadFailed;
            },
        };
    } else "";

    const response = try handler.handle(c.store, c.io, arena, .{ .method = method, .path = path, .body = body });
    try writeResponse(out, response, std.mem.eql(u8, method, "HEAD"), head.keep_alive);
    return head.keep_alive;
}

/// Sends a bodiless error response and reports that the connection must close.
fn sendError(out: *Io.Writer, status: Status) Io.Writer.Error!bool {
    try writeResponse(out, .{ .status = status }, false, false);
    return false;
}

fn writeResponse(out: *Io.Writer, response: handler.Response, omit_body: bool, keep_alive: bool) Io.Writer.Error!void {
    const status = response.status;
    try out.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase() orelse "" });
    // 1xx and 204 responses must not carry a Content-Length (RFC 9110 §8.6).
    if (status != .no_content) try out.print("Content-Length: {d}\r\n", .{response.body.len});
    if (response.content_type) |value| try out.print("Content-Type: {s}\r\n", .{value});
    if (response.allow) |value| try out.print("Allow: {s}\r\n", .{value});
    if (!keep_alive) try out.writeAll("Connection: close\r\n");
    try out.writeAll("\r\n");
    if (!omit_body) try out.writeAll(response.body);
    try out.flush();
}

/// The parts of a request head this server acts on. Slices point into the
/// buffer passed to `parse`.
const Head = struct {
    method: []const u8,
    /// Request target with any query string removed.
    path: []const u8,
    content_length: ?u64 = null,
    chunked: bool = false,
    expect_continue: bool = false,
    keep_alive: bool,

    const ParseError = error{
        InvalidRequestLine,
        UnsupportedVersion,
        InvalidHeader,
        InvalidContentLength,
        UnsupportedTransferEncoding,
        UnsupportedExpectation,
    };

    fn parse(bytes: []const u8) ParseError!Head {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        const request_line = trimCr(lines.first());

        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return error.InvalidRequestLine;
        const target = parts.next() orelse return error.InvalidRequestLine;
        const version = parts.next() orelse return error.InvalidRequestLine;
        if (parts.next() != null or !isToken(method) or target.len == 0 or target[0] != '/')
            return error.InvalidRequestLine;

        const http11 = if (std.mem.eql(u8, version, "HTTP/1.1"))
            true
        else if (std.mem.eql(u8, version, "HTTP/1.0"))
            false
        else
            return error.UnsupportedVersion;

        var head: Head = .{
            .method = method,
            .path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len],
            .keep_alive = http11,
        };

        while (lines.next()) |raw| {
            const line = trimCr(raw);
            if (line.len == 0) break;
            const colon = std.mem.findScalar(u8, line, ':') orelse return error.InvalidHeader;
            const name = line[0..colon];
            if (!isToken(name)) return error.InvalidHeader;
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");

            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                const len = std.fmt.parseUnsigned(u64, value, 10) catch return error.InvalidContentLength;
                if (head.content_length) |prev| if (prev != len) return error.InvalidContentLength;
                head.content_length = len;
            } else if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                if (!std.ascii.eqlIgnoreCase(value, "chunked")) return error.UnsupportedTransferEncoding;
                head.chunked = true;
            } else if (std.ascii.eqlIgnoreCase(name, "connection")) {
                var tokens = std.mem.tokenizeAny(u8, value, ", \t");
                while (tokens.next()) |token| {
                    if (std.ascii.eqlIgnoreCase(token, "close")) head.keep_alive = false;
                    if (std.ascii.eqlIgnoreCase(token, "keep-alive")) head.keep_alive = true;
                }
            } else if (std.ascii.eqlIgnoreCase(name, "expect")) {
                if (!std.ascii.eqlIgnoreCase(value, "100-continue")) return error.UnsupportedExpectation;
                head.expect_continue = http11;
            }
        }

        // A message with both framings is a request-smuggling vector (RFC 9112 §6.1).
        if (head.chunked and head.content_length != null) return error.InvalidContentLength;
        return head;
    }

    fn trimCr(line: []const u8) []const u8 {
        return std.mem.trimEnd(u8, line, "\r");
    }

    fn isToken(s: []const u8) bool {
        if (s.len == 0) return false;
        for (s) |ch| switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
            else => return false,
        };
        return true;
    }
};

test "Head.parse" {
    const head = try Head.parse("PUT /kv/a?x=1 HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\nConnection: close\r\n\r\n");
    try std.testing.expectEqualStrings("PUT", head.method);
    try std.testing.expectEqualStrings("/kv/a", head.path);
    try std.testing.expectEqual(5, head.content_length.?);
    try std.testing.expect(!head.keep_alive);

    const custom = try Head.parse("FROB /health HTTP/1.0\n\n");
    try std.testing.expectEqualStrings("FROB", custom.method);
    try std.testing.expect(!custom.keep_alive);

    try std.testing.expectError(error.InvalidRequestLine, Head.parse("GET\r\n\r\n"));
    try std.testing.expectError(error.UnsupportedVersion, Head.parse("GET / HTTP/2\r\n\r\n"));
    try std.testing.expectError(error.InvalidContentLength, Head.parse("GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"));
}
