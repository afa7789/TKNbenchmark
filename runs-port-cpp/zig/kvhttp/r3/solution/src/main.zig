//! kvhttp: an HTTP/1.1 in-memory key/value server.
//!
//! Usage: `app <port>` — listens on 127.0.0.1:<port> until killed.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;

const http = @import("http.zig");
const router = @import("router.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

/// How long a peer may stay silent while we are reading its request.
const read_timeout: Io.Duration = .fromSeconds(30);
/// How long to wait for the peer to finish sending after we replied.
const drain_timeout: Io.Duration = .fromSeconds(2);
/// Upper bound on unread request bytes discarded after replying.
const max_drain_bytes = 64 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        log.err("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
        std.process.exit(2);
    }
    const port = parsePort(args[1]) orelse {
        log.err("invalid port '{s}'", .{args[1]});
        std.process.exit(2);
    };

    std.process.raiseFileDescriptorLimit();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }) catch |err|
        std.process.fatal("listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer server.deinit(io);

    var store: Store = .init(gpa);
    defer store.deinit();

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                // Back off until in-flight connections release descriptors.
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => |e| return e,
        };
        connections.concurrent(io, serveConnection, .{ io, gpa, &store, stream }) catch |err| {
            log.warn("dropping connection: {t}", .{err});
            stream.close(io);
        };
    }
}

fn parsePort(arg: []const u8) ?u16 {
    if (arg.len == 0) return null;
    for (arg) |c| if (!std.ascii.isDigit(c)) return null;
    const port = std.fmt.parseInt(u16, arg, 10) catch return null;
    return if (port == 0) null else port;
}

fn serveConnection(io: Io, gpa: Allocator, store: *Store, stream: net.Stream) void {
    defer stream.close(io);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const read_buffer = arena.alloc(u8, http.read_buffer_len) catch return;
    var reader: TimedReader = .init(io, stream, read_buffer, read_timeout);

    const response: http.Response = response: {
        const request = http.readRequest(arena, &reader.interface) catch |err| {
            break :response .empty(http.errorStatus(err));
        } orelse return;
        break :response router.handle(io, arena, store, &request) catch |err| {
            log.err("request failed: {t}", .{err});
            break :response .empty(.internal_server_error);
        };
    };

    var write_buffer: [4096]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    http.writeResponse(&writer.interface, response) catch return;

    // Send FIN, then discard any unread request bytes (e.g. an oversized body
    // we rejected) so closing does not trigger a RST that could clobber the
    // reply.
    stream.shutdown(io, .send) catch return;
    reader.timeout = drain_timeout;
    var drained: usize = 0;
    while (drained < max_drain_bytes) {
        drained += reader.interface.discard(.limited(max_drain_bytes - drained)) catch break;
    }
}

/// `Io.Reader` over a TCP stream that fails with `error.ReadFailed` (and sets
/// `err` to `error.Timeout`) when the peer stays silent for longer than
/// `timeout`.
const TimedReader = struct {
    io: Io,
    socket: net.Socket,
    timeout: Io.Duration,
    interface: Io.Reader,
    err: ?net.Socket.ReceiveTimeoutError = null,

    fn init(io: Io, stream: net.Stream, buffer: []u8, timeout: Io.Duration) TimedReader {
        return .{
            .io = io,
            .socket = stream.socket,
            .timeout = timeout,
            .interface = .{
                .vtable = &.{ .stream = streamImpl },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
        };
    }

    fn streamImpl(r: *Io.Reader, w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
        const self: *TimedReader = @alignCast(@fieldParentPtr("interface", r));
        const dest = limit.slice(try w.writableSliceGreedy(1));
        const message = self.socket.receiveTimeout(self.io, dest, .{
            .duration = .{ .raw = self.timeout, .clock = .awake },
        }) catch |err| {
            self.err = err;
            return error.ReadFailed;
        };
        if (message.data.len == 0) return error.EndOfStream;
        w.advance(message.data.len);
        return message.data.len;
    }
};

test parsePort {
    try std.testing.expectEqual(8080, parsePort("8080"));
    try std.testing.expectEqual(65535, parsePort("65535"));
    try std.testing.expectEqual(null, parsePort("0"));
    try std.testing.expectEqual(null, parsePort("65536"));
    try std.testing.expectEqual(null, parsePort("+80"));
    try std.testing.expectEqual(null, parsePort(""));
}

test {
    _ = http;
    _ = router;
    _ = Store;
}
