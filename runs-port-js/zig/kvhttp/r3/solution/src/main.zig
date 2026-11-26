//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port> until killed)

const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.kvhttp);

const Store = @import("Store.zig");
const server = @import("server.zig");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port = parsePort(args) orelse {
        std.debug.print("usage: app <port>\n", .{});
        return 2;
    };

    var store: Store = .init(gpa);
    defer store.deinit();

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .kernel_backlog = 1024, .reuse_address = true }) catch |err| {
        log.err("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
        return 1;
    };
    defer listener.deinit(io);

    const ctx: server.Context = .{ .io = io, .gpa = gpa, .store = &store };

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            error.ConnectionAborted => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, server.handleConnection, .{ &ctx, stream }) catch |err| {
            log.warn("cannot spawn connection handler: {t}", .{err});
            stream.close(io);
        };
    }
}

fn parsePort(args: []const [:0]const u8) ?u16 {
    if (args.len != 2) return null;
    const port = std.fmt.parseInt(u16, args[1], 10) catch return null;
    return if (port == 0) null else port;
}

test {
    _ = Store;
    _ = server;
}

test parsePort {
    try std.testing.expectEqual(8080, parsePort(&.{ "app", "8080" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "0" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "70000" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "x" }));
    try std.testing.expectEqual(null, parsePort(&.{"app"}));
}
