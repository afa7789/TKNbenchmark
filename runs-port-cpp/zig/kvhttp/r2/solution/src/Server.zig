//! Minimal HTTP/1.1 server: one request per connection, each connection
//! served by its own concurrent task. Listens on 127.0.0.1.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;

const http = @import("http.zig");

const Server = @This();

const log = std.log.scoped(.server);

pub const Options = struct {
    port: u16,
    max_head_bytes: usize = 64 * 1024,
    max_body_bytes: usize = 1024 * 1024,
    /// Upper bound on the lifetime of a single connection.
    io_timeout: Io.Duration = .fromSeconds(10),
};

/// Produces a response for a request. All response data must be allocated
/// with `arena`, which lives until the response has been sent.
pub const Handler = struct {
    context: *anyopaque,
    handleFn: *const fn (context: *anyopaque, io: Io, arena: Allocator, request: http.Request) HandlerError!http.Response,

    pub const HandlerError = Allocator.Error || Io.Cancelable;

    fn handle(h: Handler, io: Io, arena: Allocator, request: http.Request) HandlerError!http.Response {
        return h.handleFn(h.context, io, arena, request);
    }
};

gpa: Allocator,
io: Io,
options: Options,
handler: Handler,
listener: net.Server,

pub fn listen(gpa: Allocator, io: Io, options: Options, handler: Handler) net.IpAddress.ListenError!Server {
    const address: net.IpAddress = .{ .ip4 = .loopback(options.port) };
    return .{
        .gpa = gpa,
        .io = io,
        .options = options,
        .handler = handler,
        .listener = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }),
    };
}

pub fn deinit(server: *Server) void {
    server.listener.deinit(server.io);
    server.* = undefined;
}

/// Accept loop; only returns when canceled.
pub fn run(server: *Server) Io.Cancelable!void {
    const io = server.io;
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = server.listener.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.ConnectionAborted => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                log.err("accept: {t}", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => {
                log.err("accept: {t}", .{err});
                continue;
            },
        };
        group.concurrent(io, handleConnection, .{ server, stream }) catch |err| {
            log.err("failed to spawn connection task: {t}", .{err});
            stream.close(io);
        };
    }
}

/// Errors that end a connection. Those with an HTTP status get a response.
const RequestError = error{
    BadRequest,
    ContentTooLarge,
    HeadTooLarge,
    NotImplemented,
    ConnectionClosed,
} || Allocator.Error;

fn errorStatus(err: RequestError) ?u16 {
    return switch (err) {
        error.BadRequest => 400,
        error.ContentTooLarge => 413,
        error.HeadTooLarge => 431,
        error.NotImplemented => 501,
        error.OutOfMemory => 500,
        error.ConnectionClosed => null,
    };
}

fn handleConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    // Shuts the socket down if the connection outlives its deadline, which
    // unblocks any pending read or write.
    var watchdog: ?Io.Future(Io.Cancelable!void) = io.concurrent(shutdownAfter, .{ io, stream, server.options.io_timeout }) catch |err| blk: {
        log.warn("connection served without timeout: {t}", .{err});
        break :blk null;
    };
    defer if (watchdog) |*w| w.cancel(io) catch {};

    var arena_state: std.heap.ArenaAllocator = .init(server.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const recv_buffer = arena.alloc(u8, server.options.max_head_bytes) catch return;
    var reader = stream.reader(io, recv_buffer);
    var send_buffer: [4096]u8 = undefined;
    var writer = stream.writer(io, &send_buffer);

    var conn: Connection = .{
        .reader = &reader.interface,
        .writer = &writer.interface,
        .options = &server.options,
    };

    const response, const include_body = if (conn.readRequest(arena)) |request| blk: {
        const response = server.handler.handle(io, arena, request) catch |err| switch (err) {
            error.Canceled => return,
            error.OutOfMemory => http.Response.text(500, "Internal Server Error"),
        };
        break :blk .{ response, !std.mem.eql(u8, request.method, "HEAD") };
    } else |err| blk: {
        const status = errorStatus(err) orelse return;
        break :blk .{ http.Response.text(status, http.reasonPhrase(status)), true };
    };

    conn.send(response, include_body) catch return;
    conn.lingerClose(stream, io);
}

fn shutdownAfter(io: Io, stream: net.Stream, timeout: Io.Duration) Io.Cancelable!void {
    try io.sleep(timeout, .awake);
    stream.shutdown(io, .both) catch {};
}

const Connection = struct {
    reader: *Io.Reader,
    writer: *Io.Writer,
    options: *const Options,

    fn readRequest(conn: *Connection, arena: Allocator) RequestError!http.Request {
        // The head is copied out of the receive buffer, which is reused for the body.
        const head = try arena.dupe(u8, try conn.readHead());
        var request = http.parseHead(arena, head) catch |err| switch (err) {
            error.MalformedRequest => return error.BadRequest,
            error.OutOfMemory => |e| return e,
        };
        request.body = try conn.readBody(arena, request);
        return request;
    }

    /// Returns the request head without its terminating blank line.
    fn readHead(conn: *Connection) RequestError![]const u8 {
        const r = conn.reader;
        var scan_from: usize = 0;
        while (true) {
            const buffered = r.buffered();
            if (std.mem.indexOfPos(u8, buffered, scan_from, "\r\n\r\n")) |end| {
                r.toss(end + 4);
                return buffered[0..end];
            }
            if (buffered.len == r.buffer.len) return error.HeadTooLarge;
            scan_from = buffered.len -| 3;
            r.fillMore() catch return error.ConnectionClosed;
        }
    }

    fn readBody(conn: *Connection, arena: Allocator, request: http.Request) RequestError![]const u8 {
        if (request.header("Transfer-Encoding")) |te| {
            if (!std.ascii.eqlIgnoreCase(te, "chunked")) return error.NotImplemented;
            return conn.readChunkedBody(arena);
        }
        const length_text = request.header("Content-Length") orelse return "";
        const length = http.parseUnsigned(usize, length_text, 10) catch |err| switch (err) {
            error.Overflow => return error.ContentTooLarge,
            error.InvalidCharacter => return error.BadRequest,
        };
        if (length > conn.options.max_body_bytes) return error.ContentTooLarge;

        const body = try arena.alloc(u8, length);
        try conn.readExact(body);
        return body;
    }

    fn readChunkedBody(conn: *Connection, arena: Allocator) RequestError![]const u8 {
        var body: std.ArrayList(u8) = .empty;
        while (true) {
            const line = try conn.readLine();
            const size_text = line[0 .. std.mem.indexOfScalar(u8, line, ';') orelse line.len];
            const size = http.parseUnsigned(usize, size_text, 16) catch return error.BadRequest;
            if (size == 0) {
                // Discard trailer fields up to the terminating blank line.
                while ((try conn.readLine()).len != 0) {}
                return body.items;
            }
            if (size > conn.options.max_body_bytes - body.items.len) return error.ContentTooLarge;
            try conn.readExact(try body.addManyAsSlice(arena, size));
            if ((try conn.readLine()).len != 0) return error.BadRequest;
        }
    }

    fn readExact(conn: *Connection, dest: []u8) RequestError!void {
        conn.reader.readSliceAll(dest) catch |err| return switch (err) {
            error.EndOfStream => error.BadRequest,
            error.ReadFailed => error.ConnectionClosed,
        };
    }

    /// Returns the next CRLF-terminated line, without the terminator. The
    /// slice is only valid until the next read.
    fn readLine(conn: *Connection) RequestError![]const u8 {
        const line = conn.reader.takeDelimiterInclusive('\n') catch |err| return switch (err) {
            error.EndOfStream, error.StreamTooLong => error.BadRequest,
            error.ReadFailed => error.ConnectionClosed,
        };
        if (!std.mem.endsWith(u8, line, "\r\n")) return error.BadRequest;
        return line[0 .. line.len - 2];
    }

    fn send(conn: *Connection, response: http.Response, include_body: bool) error{ConnectionClosed}!void {
        const w = conn.writer;
        response.writeHead(w) catch return error.ConnectionClosed;
        if (include_body) w.writeAll(response.body) catch return error.ConnectionClosed;
        w.flush() catch return error.ConnectionClosed;
    }

    /// Half-closes the socket and discards any remaining input so the client
    /// sees the response rather than a reset.
    fn lingerClose(conn: *Connection, stream: net.Stream, io: Io) void {
        const max_drain = 16 * 1024 * 1024;
        stream.shutdown(io, .send) catch return;
        _ = conn.reader.discard(.limited(max_drain)) catch {};
    }
};
