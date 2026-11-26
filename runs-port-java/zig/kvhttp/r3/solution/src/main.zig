//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>
//! Listens on 127.0.0.1:<port> and serves until killed.

const std = @import("std");
const Io = std.Io;
const net = Io.net;

const Store = @import("Store.zig");
const Connection = @import("Connection.zig");

const log = std.log.scoped(.kvhttp);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        log.err("usage: app <port>", .{});
        std.process.exit(2);
    }
    const port = std.fmt.parseInt(u16, args[1], 10) catch {
        log.err("invalid port: {s}", .{args[1]});
        std.process.exit(2);
    };

    var store: Store = .init(gpa);
    defer store.deinit();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = try address.listen(io, .{ .kernel_backlog = 1024, .reuse_address = true });
    defer server.deinit(io);

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => return,
            // Transient conditions (aborted handshakes, descriptor or memory
            // exhaustion) must not bring the server down.
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, Connection.handle, .{ &store, io, gpa, stream }) catch |err| {
            log.warn("serving connection inline: {t}", .{err});
            Connection.handle(&store, io, gpa, stream);
        };
    }
}

test {
    _ = Store;
    _ = Connection;
    _ = @import("route.zig");
}
