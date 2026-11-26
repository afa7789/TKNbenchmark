//! Accept loop and per-connection request handling.
//!
//! Each connection runs as its own concurrent task and serves exactly one
//! request. Reads are bounded by an idle timeout so that stalled clients
//! cannot pin a task forever.
const Server = @This();

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const posix = std.posix;
const Allocator = std.mem.Allocator;

const Store = @import("Store.zig");
const http = @import("http.zig");

const log = std.log.scoped(.server);

pub const max_head_bytes = 16 * 1024;
pub const max_key_len = 64;
pub const max_value_bytes = 1 << 20;
/// Idle timeout for each read from a client.
const read_timeout_ms = 10_000;
/// Upper bound on what is drained from a client after replying.
const drain_limit = 4 * 1024 * 1024;

io: Io,
gpa: Allocator,
store: *Store,

/// Accepts connections forever, serving each one concurrently. Returns only
/// on an unrecoverable accept error.
pub fn run(s: *Server, listener: *net.Server) !void {
    var group: Io.Group = .init;
    defer group.cancel(s.io);

    while (true) {
        const stream = listener.accept(s.io) catch |err| switch (err) {
            error.ConnectionAborted, error.ProtocolFailure, error.BlockedByFirewall, error.WouldBlock => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                // Resource pressure: back off briefly and let connections drain.
                try s.io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => |e| return e,
        };
        configureClient(stream);

        group.concurrent(s.io, handleConnection, .{ s, stream }) catch {
            var conn: Connection = undefined;
            conn.init(s, stream);
            conn.respond(.{ .status = .service_unavailable }) catch {};
            stream.close(s.io);
        };
    }
}

fn configureClient(stream: net.Stream) void {
    const one = std.mem.toBytes(@as(c_int, 1));
    posix.setsockopt(stream.socket.handle, posix.IPPROTO.TCP, posix.TCP.NODELAY, &one) catch {};
}

fn handleConnection(s: *Server, stream: net.Stream) void {
    var conn: Connection = undefined;
    conn.init(s, stream);
    defer conn.lingeringClose();
    conn.serve() catch |err| log.debug("connection ended: {t}", .{err});
}

const Connection = struct {
    server: *Server,
    stream: net.Stream,
    reader: net.Stream.Reader,
    writer: net.Stream.Writer,
    read_buf: [max_head_bytes]u8,
    write_buf: [1024]u8,

    const ReadError = error{ Timeout, EndOfStream, ReadFailed } || posix.PollError;

    /// Initializes in place: the reader and writer refer to buffers inside
    /// the connection, so it must not be moved afterwards.
    fn init(c: *Connection, s: *Server, stream: net.Stream) void {
        c.server = s;
        c.stream = stream;
        c.reader = stream.reader(s.io, &c.read_buf);
        c.writer = stream.writer(s.io, &c.write_buf);
    }

    fn respond(c: *Connection, r: http.Response) Io.Writer.Error!void {
        try r.write(&c.writer.interface);
    }

    /// Waits until the socket is readable or the idle timeout expires.
    fn waitReadable(c: *Connection) (error{Timeout} || posix.PollError)!void {
        var fds = [_]posix.pollfd{.{ .fd = c.stream.socket.handle, .events = posix.POLL.IN, .revents = 0 }};
        if (try posix.poll(&fds, read_timeout_ms) == 0) return error.Timeout;
    }

    /// Reads at least one more byte into the reader's buffer.
    fn fillMore(c: *Connection) ReadError!void {
        try c.waitReadable();
        try c.reader.interface.fillMore();
    }

    fn serve(c: *Connection) !void {
        const r = &c.reader.interface;
        const head_len = c.readHead() catch |err| switch (err) {
            error.HeadTooLarge => return c.respond(.{ .status = .request_header_fields_too_large }),
            error.NulInHead => return c.respond(.{ .status = .bad_request }),
            error.Timeout => {
                if (r.bufferedLen() > 0) try c.respond(.{ .status = .request_timeout });
                return err;
            },
            else => |e| return e,
        };

        switch (http.parseHead(r.buffered()[0..head_len])) {
            .reject => |status| try c.respond(.{ .status = status }),
            .request => |req| {
                r.toss(head_len + "\r\n\r\n".len);
                try c.route(req);
            },
        }
    }

    /// Buffers the request head; returns its length excluding the final
    /// CRLFCRLF, which is left in the buffer just after it.
    fn readHead(c: *Connection) (ReadError || error{ HeadTooLarge, NulInHead })!usize {
        const r = &c.reader.interface;
        var scanned: usize = 0;
        while (true) {
            const buf = r.buffered();
            // Resume the search a few bytes back so a terminator split across
            // reads is still found.
            const from = scanned -| 3;
            if (std.mem.indexOfPos(u8, buf, from, "\r\n\r\n")) |end| {
                if (std.mem.indexOfScalar(u8, buf[from..end], 0) != null) return error.NulInHead;
                return end;
            }
            if (std.mem.indexOfScalar(u8, buf[from..], 0) != null) return error.NulInHead;
            if (buf.len == max_head_bytes) return error.HeadTooLarge;
            scanned = buf.len;
            try c.fillMore();
        }
    }

    fn route(c: *Connection, req: http.Request) !void {
        const method = req.method;
        const target = req.target;

        if (std.mem.eql(u8, target, "/health")) {
            if (!std.mem.eql(u8, method, "GET")) return c.respond(.{ .status = .method_not_allowed, .allow = "GET" });
            return c.respond(.{ .status = .ok, .content_type = "text/plain; charset=utf-8", .body = "ok" });
        }

        if (std.mem.eql(u8, target, "/kv")) {
            if (!std.mem.eql(u8, method, "GET")) return c.respond(.{ .status = .method_not_allowed, .allow = "GET" });
            return c.handleList();
        }

        if (std.mem.startsWith(u8, target, "/kv/")) {
            const key = target["/kv/".len..];
            if (!isValidKey(key)) return c.respond(.{ .status = .bad_request });
            if (std.mem.eql(u8, method, "GET")) return c.handleGet(key);
            if (std.mem.eql(u8, method, "PUT")) return c.handlePut(key, req.content_length orelse 0);
            if (std.mem.eql(u8, method, "DELETE")) {
                const deleted = try c.server.store.delete(c.server.io, key);
                return c.respond(.{ .status = if (deleted) .no_content else .not_found });
            }
            return c.respond(.{ .status = .method_not_allowed, .allow = "GET, PUT, DELETE" });
        }

        return c.respond(.{ .status = .not_found });
    }

    fn handleList(c: *Connection) !void {
        var arena_state: std.heap.ArenaAllocator = .init(c.server.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const keys = c.server.store.listKeys(c.server.io, arena) catch |err| switch (err) {
            error.OutOfMemory => return c.respond(.{ .status = .internal_server_error }),
            else => |e| return e,
        };
        const json = keysToJson(arena, keys) catch return c.respond(.{ .status = .internal_server_error });
        return c.respond(.{ .status = .ok, .content_type = "application/json", .body = json });
    }

    fn handleGet(c: *Connection, key: []const u8) !void {
        const gpa = c.server.gpa;
        const value = c.server.store.get(c.server.io, gpa, key) catch |err| switch (err) {
            error.OutOfMemory => return c.respond(.{ .status = .internal_server_error }),
            else => |e| return e,
        } orelse return c.respond(.{ .status = .not_found });
        defer gpa.free(value);
        return c.respond(.{ .status = .ok, .content_type = "application/octet-stream", .body = value });
    }

    fn handlePut(c: *Connection, request_key: []const u8, len: usize) !void {
        if (len > max_value_bytes) return c.respond(.{ .status = .payload_too_large });

        // The key points into the read buffer, which reading the body may
        // overwrite; keep a copy.
        var key_buf: [max_key_len]u8 = undefined;
        const key = key_buf[0..request_key.len];
        @memcpy(key, request_key);

        const gpa = c.server.gpa;
        const value = gpa.alloc(u8, len) catch return c.respond(.{ .status = .internal_server_error });
        errdefer gpa.free(value);
        try c.readBody(value);

        const result = c.server.store.put(c.server.io, key, value) catch |err| switch (err) {
            error.OutOfMemory => return c.respond(.{ .status = .internal_server_error }),
            else => |e| return e,
        };
        return c.respond(.{ .status = switch (result) {
            .created => .created,
            .replaced => .ok,
        } });
    }

    /// Fills `dest` with the request body, starting with any bytes that were
    /// received together with the head.
    fn readBody(c: *Connection, dest: []u8) ReadError!void {
        const r = &c.reader.interface;
        var filled = @min(r.bufferedLen(), dest.len);
        @memcpy(dest[0..filled], r.buffered()[0..filled]);
        r.toss(filled);

        while (filled < dest.len) {
            try c.waitReadable();
            // The reader's buffer is empty here, so this issues a single read
            // directly into `dest`.
            var bufs: [1][]u8 = .{dest[filled..]};
            filled += try r.readVec(&bufs);
        }
    }

    /// Half-closes the connection and drains whatever the peer still sends,
    /// so that closing does not reset the connection before the client has
    /// read the reply.
    fn lingeringClose(c: *Connection) void {
        const io = c.server.io;
        defer c.stream.close(io);
        c.stream.shutdown(io, .send) catch return;

        const r = &c.reader.interface;
        var drained: usize = 0;
        while (drained < drain_limit) {
            drained += r.bufferedLen();
            r.tossBuffered();
            c.fillMore() catch break;
        }
    }
};

fn isValidKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_key_len) return false;
    for (key) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '-') return false;
    }
    return true;
}

/// Renders keys as a JSON array of strings. Keys are restricted to
/// `[A-Za-z0-9_-]`, so no escaping is needed.
fn keysToJson(arena: Allocator, keys: []const []const u8) Allocator.Error![]const u8 {
    var len: usize = "[]".len;
    for (keys) |key| len += key.len + "\"\",".len;

    var out: std.ArrayList(u8) = try .initCapacity(arena, len);
    out.appendAssumeCapacity('[');
    for (keys, 0..) |key, i| {
        if (i > 0) out.appendAssumeCapacity(',');
        out.appendAssumeCapacity('"');
        out.appendSliceAssumeCapacity(key);
        out.appendAssumeCapacity('"');
    }
    out.appendAssumeCapacity(']');
    return out.items;
}

test isValidKey {
    try std.testing.expect(isValidKey("a"));
    try std.testing.expect(isValidKey("A-z_09"));
    try std.testing.expect(isValidKey("k" ** 64));
    try std.testing.expect(!isValidKey("k" ** 65));
    try std.testing.expect(!isValidKey(""));
    try std.testing.expect(!isValidKey("a/b"));
    try std.testing.expect(!isValidKey("bad.key"));
}

test keysToJson {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("[]", try keysToJson(arena.allocator(), &.{}));
    try std.testing.expectEqualStrings("[\"a\",\"b\"]", try keysToJson(arena.allocator(), &.{ "a", "b" }));
}
