//! Entry point: `app <port>` serves the kvhttp API on 127.0.0.1:<port>.

const std = @import("std");
const Io = std.Io;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const port = parsePort(init.minimal.args) orelse {
        std.debug.print("usage: app <port>\n", .{});
        std.process.exit(2);
    };

    var store: Store = .init(init.gpa);
    defer store.deinit();

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer listener.deinit(io);

    const server: Server = .{ .io = io, .gpa = init.gpa, .store = &store };
    try server.serve(&listener);
}

fn parsePort(args: std.process.Args) ?u16 {
    var it = args.iterate();
    _ = it.skip();
    const arg = it.next() orelse return null;
    if (it.next() != null) return null;
    const port = std.fmt.parseInt(u16, arg, 10) catch return null;
    return if (port == 0) null else port;
}

test {
    _ = @import("route.zig");
    _ = @import("Store.zig");
    _ = @import("Server.zig");
}
