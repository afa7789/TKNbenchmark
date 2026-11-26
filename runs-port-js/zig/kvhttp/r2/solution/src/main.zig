//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>
//! Listens on 127.0.0.1:<port> until killed.

const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port = parsePort(args) orelse {
        log.err("usage: app <port>", .{});
        std.process.exit(2);
    };

    // A client hanging up mid-response must surface as a write error, not
    // terminate the process.
    ignoreSigpipe();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }) catch |err| {
        log.err("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
        std.process.exit(1);
    };
    defer listener.deinit(io);

    var store: Store = .init(gpa);
    defer store.deinit();
    var server: Server = .{ .io = io, .gpa = gpa, .store = &store };

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return,
            error.ConnectionAborted, error.WouldBlock => continue,
            else => {
                // Typically descriptor exhaustion; back off instead of spinning.
                log.warn("accept failed: {t}", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
        };
        connections.concurrent(io, Server.serveConnection, .{ &server, stream }) catch {
            // No worker thread available: serve inline rather than drop it.
            server.serveConnection(stream);
        };
    }
}

fn parsePort(args: []const [:0]const u8) ?u16 {
    if (args.len != 2) return null;
    const port = std.fmt.parseUnsigned(u16, args[1], 10) catch return null;
    return if (port == 0) null else port;
}

fn ignoreSigpipe() void {
    const posix = std.posix;
    const action: posix.Sigaction = .{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(.PIPE, &action, null);
}

test {
    std.testing.refAllDecls(@This());
    _ = Server;
    _ = Store;
}

test parsePort {
    try std.testing.expectEqual(8080, parsePort(&.{ "app", "8080" }));
    try std.testing.expectEqual(null, parsePort(&.{"app"}));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "0" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "70000" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "x" }));
}
