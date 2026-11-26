//! `app <port>` serves the key-value API on 127.0.0.1:<port> until killed.

const std = @import("std");
const net = std.Io.net;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

const listen_backlog = 1024;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var args = init.minimal.args.iterate();
    _ = args.skip();
    const port_arg = args.next() orelse usage();
    if (args.next() != null) usage();
    const port = std.fmt.parseInt(u16, port_arg, 10) catch
        std.process.fatal("invalid port: {s}", .{port_arg});

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{
        .kernel_backlog = listen_backlog,
        .reuse_address = true,
    }) catch |err| std.process.fatal("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer listener.deinit(io);

    var store: Store = .init(init.gpa);
    defer store.deinit();

    var server: Server = .{ .io = io, .gpa = init.gpa, .store = &store };
    try server.run(&listener);
}

fn usage() noreturn {
    std.process.fatal("usage: app <port>", .{});
}

test {
    _ = @import("http.zig");
    _ = @import("router.zig");
    _ = @import("Store.zig");
    _ = Server;
}
