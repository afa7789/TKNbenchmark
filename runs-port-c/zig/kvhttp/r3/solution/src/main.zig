//! kvhttp: an in-memory HTTP/1.1 key-value server. Usage: app <port>

const std = @import("std");
const net = std.Io.net;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    var args = init.minimal.args.iterate();
    const argv0 = args.next() orelse "app";
    const port = blk: {
        const arg = args.next() orelse break :blk null;
        if (args.next() != null) break :blk null;
        break :blk parsePort(arg);
    } orelse {
        std.log.err("usage: {s} <port>", .{argv0});
        return 2;
    };

    ignoreSigpipe();
    // Every connection holds a descriptor; allow as many as the hard limit permits.
    std.process.raiseFileDescriptorLimit();

    var store: Store = .init(init.gpa);
    defer store.deinit();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .reuse_address = true }) catch |err| {
        std.log.err("listen on 127.0.0.1:{d}: {t}", .{ port, err });
        return 1;
    };
    defer listener.deinit(io);

    var server: Server = .{ .io = io, .gpa = init.gpa, .store = &store, .options = .{} };
    server.serve(&listener) catch |err| {
        std.log.err("accept: {t}", .{err});
        return 1;
    };
    return 0;
}

fn parsePort(s: []const u8) ?u16 {
    const port = std.fmt.parseInt(u16, s, 10) catch return null;
    return if (port == 0) null else port;
}

/// Writes to a peer that has gone away must fail with an error, not kill the process.
fn ignoreSigpipe() void {
    const posix = std.posix;
    const act: posix.Sigaction = .{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(.PIPE, &act, null);
}

test {
    _ = @import("http.zig");
    _ = @import("routes.zig");
    _ = @import("Store.zig");
}

test parsePort {
    try std.testing.expectEqual(@as(?u16, 8080), parsePort("8080"));
    try std.testing.expectEqual(null, parsePort("0"));
    try std.testing.expectEqual(null, parsePort("65536"));
    try std.testing.expectEqual(null, parsePort("-1"));
    try std.testing.expectEqual(null, parsePort("80x"));
}
