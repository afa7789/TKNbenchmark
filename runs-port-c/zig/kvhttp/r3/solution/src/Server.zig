//! Connection handling: one concurrent task per accepted connection, one
//! request per connection, each bounded by I/O deadlines.

const Server = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = Io.net;
const log = std.log.scoped(.server);

const http = @import("http.zig");
const routes = @import("routes.zig");
const Store = @import("Store.zig");

io: Io,
gpa: Allocator,
store: *Store,
options: Options,

pub const Options = struct {
    /// Overall budget for receiving the request and sending the response.
    io_timeout: Io.Duration = .fromSeconds(30),
    /// Lingering-close budget for draining unread input after the response.
    drain_timeout: Io.Duration = .fromSeconds(2),
    /// Largest accepted request head, including the terminating blank line.
    max_head_len: usize = 64 * 1024,
    /// Size of the per-connection send buffer.
    write_buffer_len: usize = 8 * 1024,
};

/// Accepts connections until the listener fails or the task is canceled.
pub fn serve(server: *Server, listener: *net.Server) net.Server.AcceptError!void {
    const io = server.io;
    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.ConnectionAborted => continue,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.SystemResources,
            => {
                // Back off briefly so in-flight connections can finish and free resources.
                log.warn("accept: {t}", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => |e| return e,
        };
        setNoDelay(stream);
        group.concurrent(io, serveConnection, .{ server, stream }) catch |err| {
            log.warn("dropping connection: {t}", .{err});
            stream.close(io);
        };
    }
}

fn setNoDelay(stream: net.Stream) void {
    const posix = std.posix;
    const one: c_int = 1;
    posix.setsockopt(stream.socket.handle, posix.IPPROTO.TCP, posix.TCP.NODELAY, std.mem.asBytes(&one)) catch {};
}

/// Supervises one connection: runs it as a separate task and cancels that
/// task if it misses its deadline. Cancelation interrupts blocking reads and
/// writes, which a shutdown(2) from another thread does not do on every OS.
fn serveConnection(server: *Server, stream: net.Stream) void {
    const io = server.io;
    defer stream.close(io);

    var conn: Connection = .{ .server = server, .stream = stream };
    var task = io.concurrent(Connection.run, .{&conn}) catch |err| {
        log.warn("dropping connection: {t}", .{err});
        return;
    };

    const phases = [_]struct { *Io.Event, Io.Duration }{
        .{ &conn.responded, server.options.io_timeout },
        .{ &conn.finished, server.options.drain_timeout },
    };
    for (phases) |phase| {
        const event, const timeout = phase;
        event.waitTimeout(io, .{ .duration = .{ .raw = timeout, .clock = .awake } }) catch |err| {
            log.debug("connection {s}", .{if (err == error.Timeout) "timed out" else "canceled"});
            return task.cancel(io);
        };
    }
    task.await(io);
}

const Connection = struct {
    server: *Server,
    stream: net.Stream,
    /// Set once the response is sent or the exchange has failed.
    responded: Io.Event = .unset,
    /// Set when the connection task is about to return.
    finished: Io.Event = .unset,

    fn run(conn: *Connection) void {
        const server = conn.server;
        const io = server.io;
        defer {
            conn.responded.set(io);
            conn.finished.set(io);
        }

        var arena_state: std.heap.ArenaAllocator = .init(server.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const read_buffer = arena.alloc(u8, server.options.max_head_len) catch return;
        const write_buffer = arena.alloc(u8, server.options.write_buffer_len) catch return;
        var reader = conn.stream.reader(io, read_buffer);
        var writer = conn.stream.writer(io, write_buffer);

        server.exchange(arena, &reader.interface, &writer.interface) catch |err| {
            log.debug("connection dropped: {t}", .{err});
            return;
        };
        conn.responded.set(io);

        // Half-close and drain so that unread request bytes do not trigger a
        // RST that could discard the response before the client reads it.
        conn.stream.shutdown(io, .send) catch return;
        _ = reader.interface.discardRemaining() catch {};
    }
};

const ExchangeError = error{ ReadFailed, EndOfStream, WriteFailed };

/// Reads one request and writes its response.
fn exchange(server: *Server, arena: Allocator, r: *Io.Reader, w: *Io.Writer) ExchangeError!void {
    const res = try server.readAndHandle(arena, r, w);
    try http.writeResponse(w, res.status, res.content_type, res.body);
    try w.flush();
}

fn readAndHandle(server: *Server, arena: Allocator, r: *Io.Reader, w: *Io.Writer) ExchangeError!routes.Response {
    const head_len = while (true) {
        if (http.headLength(r.buffered())) |n| break n;
        if (r.bufferedLen() >= server.options.max_head_len)
            return .empty(.request_header_fields_too_large);
        try r.fillMore();
    };

    // Copy the head out of the read buffer, which reading the body may reuse.
    const head = arena.dupe(u8, r.buffered()[0..head_len]) catch
        return .empty(.internal_server_error);
    r.toss(head_len);

    const req = http.parseHead(head) catch |err| return .empty(http.statusForError(err));
    if (req.content_length > routes.max_value_len) return .empty(.content_too_large);

    const body = arena.alloc(u8, req.content_length) catch return .empty(.internal_server_error);
    if (req.expect_continue and r.bufferedLen() < body.len) {
        try w.writeAll(http.continue_line);
        try w.flush();
    }
    try r.readSliceAll(body);

    return routes.handle(server.store, server.io, arena, req, body);
}
