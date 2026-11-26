//! kvhttp: an in-memory key-value store served over HTTP/1.1.
//!
//! Usage: `app <port>` listens on 127.0.0.1:<port> until killed.

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
    const port = parsePort(args) orelse {
        std.log.err("usage: app <port>", .{});
        std.process.exit(2);
    };

    var store: Store = .init(gpa);
    defer store.deinit();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer server.deinit(io);
    log.info("listening on 127.0.0.1:{d}", .{port});

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => {
                log.warn("accept failed: {t}", .{err});
                continue;
            },
        };
        const connection: Connection = .{ .store = &store, .io = io, .gpa = gpa, .stream = stream };
        connections.concurrent(io, Connection.serve, .{connection}) catch |err| {
            log.warn("cannot serve connection: {t}", .{err});
            stream.close(io);
        };
    }
}

fn parsePort(args: []const [:0]const u8) ?u16 {
    if (args.len != 2) return null;
    const port = std.fmt.parseUnsigned(u16, args[1], 10) catch return null;
    return if (port == 0) null else port;
}

test {
    std.testing.refAllDecls(@This());
    _ = Store;
    _ = Connection;
    _ = @import("handler.zig");
}
