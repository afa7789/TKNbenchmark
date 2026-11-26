//! kvhttp: an HTTP/1.1 in-memory key-value server.
//! Usage: ./app <port>  (listens on 127.0.0.1)
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const net = Io.net;

const http = @import("http.zig");
const routes = @import("routes.zig");
const Store = @import("Store.zig");

const max_value = 1024 * 1024;
/// Upper bound on a whole request/response exchange.
const io_timeout: Io.Duration = .fromSeconds(30);
/// How long to drain unread request bytes after responding.
const linger_timeout: Io.Duration = .fromMilliseconds(500);
const linger_max_bytes = 4 * max_value;

const log = std.log.scoped(.kvhttp);

const Server = struct {
    io: Io,
    gpa: Allocator,
    store: Store,

    fn serveConnection(server: *Server, stream: net.Stream) void {
        const io = server.io;
        defer stream.close(io);

        var arena_state: std.heap.ArenaAllocator = .init(server.gpa);
        defer arena_state.deinit();

        var in_buf: [http.head_max]u8 = undefined;
        var out_buf: [1024]u8 = undefined;
        var reader = stream.reader(io, &in_buf);
        var writer = stream.writer(io, &out_buf);

        const responded = responded: {
            var watchdog = Watchdog.start(io, stream, io_timeout);
            defer watchdog.stop(io);
            break :responded server.exchange(arena_state.allocator(), &reader.interface, &writer.interface);
        };
        if (responded) lingeringClose(io, stream, &reader.interface);
    }

    /// Reads one request and answers it. Returns false when the peer went
    /// away before a response could be attempted.
    fn exchange(server: *Server, arena: Allocator, in: *Io.Reader, out: *Io.Writer) bool {
        const req = http.readRequest(arena, in, out, max_value) catch |err| switch (err) {
            error.ConnectionClosed => return false,
            else => |e| {
                http.respond(out, http.statusFor(e), null, "") catch {};
                return true;
            },
        };
        const res = routes.handle(&server.store, server.io, arena, req) catch
            routes.Response{ .status = .internal_server_error };
        defer if (res.blob) |blob| server.store.release(blob);
        http.respond(out, res.status, res.content_type, res.body) catch {};
        return true;
    }
};

/// Shuts a connection down once a timeout elapses, unblocking any pending
/// read or write on it.
const Watchdog = struct {
    future: ?Io.Future(Io.Cancelable!void),

    fn start(io: Io, stream: net.Stream, timeout: Io.Duration) Watchdog {
        const future = io.concurrent(expire, .{ io, stream, timeout }) catch |err| {
            log.warn("connection runs without a timeout: {t}", .{err});
            return .{ .future = null };
        };
        return .{ .future = future };
    }

    fn stop(w: *Watchdog, io: Io) void {
        if (w.future) |*f| f.cancel(io) catch {};
    }

    fn expire(io: Io, stream: net.Stream, timeout: Io.Duration) Io.Cancelable!void {
        try io.sleep(timeout, .awake);
        stream.shutdown(io, .both) catch {};
    }
};

/// Half-closes and drains, so unread request bytes do not turn our close into
/// a RST that could destroy the response before the client reads it.
fn lingeringClose(io: Io, stream: net.Stream, in: *Io.Reader) void {
    stream.shutdown(io, .send) catch return;
    var watchdog = Watchdog.start(io, stream, linger_timeout);
    defer watchdog.stop(io);
    _ = in.discardShort(linger_max_bytes) catch {};
}

fn rejectBusy(io: Io, stream: net.Stream) void {
    defer stream.close(io);
    var out_buf: [256]u8 = undefined;
    var writer = stream.writer(io, &out_buf);
    http.respond(&writer.interface, .internal_server_error, null, "") catch {};
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    var args = init.minimal.args.iterate();
    const argv0 = args.next() orelse "app";
    const port_arg = args.next();
    const port = if (port_arg) |arg| std.fmt.parseInt(u16, arg, 10) catch 0 else 0;
    if (port == 0 or args.next() != null) {
        std.debug.print("usage: {s} <port>\n", .{argv0});
        return 2;
    }

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .reuse_address = true }) catch |err| {
        log.err("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
        return 1;
    };
    defer listener.deinit(io);

    var server: Server = .{ .io = io, .gpa = init.gpa, .store = .init(init.gpa) };
    defer server.store.deinit();

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.ConnectionAborted => continue,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.SystemResources,
            => {
                // Resource exhaustion: back off briefly instead of spinning.
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => |e| {
                log.err("accept failed: {t}", .{e});
                return 1;
            },
        };
        connections.concurrent(io, Server.serveConnection, .{ &server, stream }) catch {
            rejectBusy(io, stream);
        };
    }
}

test {
    _ = http;
    _ = routes;
    _ = Store;
}
