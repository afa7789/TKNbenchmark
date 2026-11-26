//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>

const std = @import("std");
const net = std.Io.net;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

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
    var listener = address.listen(io, .{ .kernel_backlog = 511, .reuse_address = true }) catch |err| {
        std.log.err("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
        std.process.exit(1);
    };
    defer listener.deinit(io);

    std.log.info("kvhttp listening on http://127.0.0.1:{d}", .{port});

    var server: Server = .{ .io = io, .gpa = gpa, .store = &store };
    try server.run(&listener);
}

fn parsePort(args: []const [:0]const u8) ?u16 {
    if (args.len != 2) return null;
    const port = std.fmt.parseInt(u16, args[1], 10) catch return null;
    return if (port == 0) null else port;
}

test parsePort {
    try std.testing.expectEqual(8080, parsePort(&.{ "app", "8080" }));
    try std.testing.expectEqual(null, parsePort(&.{"app"}));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "0" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "65536" }));
    try std.testing.expectEqual(null, parsePort(&.{ "app", "http" }));
}

test {
    _ = @import("http.zig");
    _ = Server;
    _ = Store;
}
