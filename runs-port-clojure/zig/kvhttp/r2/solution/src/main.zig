//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port>)

const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Store = @import("Store.zig");
const server = @import("server.zig");

const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port = parsePort(args) orelse {
        std.debug.print("usage: app <port>\n", .{});
        std.process.exit(2);
    };

    var store: Store = .init(gpa);
    defer store.deinit();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer listener.deinit(io);

    const ctx: server.Context = .{ .io = io, .gpa = gpa, .store = &store };

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, server.serveConnection, .{ &ctx, stream }) catch |err| {
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
    _ = @import("Store.zig");
    _ = @import("routes.zig");
    _ = @import("server.zig");
}
