//! kvhttp: an in-memory key-value store served over HTTP/1.1.
//!
//! Usage: `app <port>` listens on 127.0.0.1:<port> until killed.

const std = @import("std");
const Io = std.Io;

const Connection = @import("Connection.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

const kernel_backlog = 1024;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        log.err("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
        return 2;
    }
    const port = std.fmt.parseInt(u16, args[1], 10) catch {
        log.err("invalid port: {s}", .{args[1]});
        return 2;
    };

    var store: Store = .init(gpa);
    defer store.deinit();
    const ctx: Connection.Context = .{ .io = io, .gpa = gpa, .store = &store };

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = address.listen(io, .{ .kernel_backlog = kernel_backlog, .reuse_address = true }) catch |err| {
        log.err("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
        return 1;
    };
    defer server.deinit(io);

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => return err,
            error.ConnectionAborted => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        connections.concurrent(io, Connection.serve, .{ &ctx, stream }) catch {
            // No spare thread is available; serve on the accept loop instead.
            Connection.serve(&ctx, stream);
        };
    }
}

test {
    _ = Connection;
    _ = Store;
    _ = @import("route.zig");
}
