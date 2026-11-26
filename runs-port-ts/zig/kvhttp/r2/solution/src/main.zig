//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port> until killed)

const std = @import("std");
const Io = std.Io;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port = parsePort(if (args.len > 1) args[1] else null) orelse {
        std.debug.print("usage: app <port>\n", .{});
        return 2;
    };

    var store: Store = .init(gpa);
    defer store.deinit();

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .kernel_backlog = 1024, .reuse_address = true }) catch |err| {
        std.debug.print("server error: listen on 127.0.0.1:{d}: {t}\n", .{ port, err });
        return 1;
    };
    defer listener.deinit(io);

    var server: Server = .{ .io = io, .gpa = gpa, .store = &store };
    server.serve(&listener) catch |err| {
        std.debug.print("server error: {t}\n", .{err});
        return 1;
    };
    return 0;
}

fn parsePort(arg: ?[]const u8) ?u16 {
    const port = std.fmt.parseUnsigned(u16, arg orelse return null, 10) catch return null;
    return if (port == 0) null else port;
}

test parsePort {
    try std.testing.expectEqual(8080, parsePort("8080"));
    try std.testing.expectEqual(null, parsePort("0"));
    try std.testing.expectEqual(null, parsePort("65536"));
    try std.testing.expectEqual(null, parsePort("x"));
    try std.testing.expectEqual(null, parsePort(null));
}

test {
    _ = @import("request.zig");
    _ = Server;
    _ = Store;
}
