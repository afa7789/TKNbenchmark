//! kvhttp: a minimal HTTP/1.1 in-memory key-value server.
//!
//! Usage: app <port>. Listens on 127.0.0.1:<port> and serves until killed.
const std = @import("std");
const Io = std.Io;

const Server = @import("Server.zig");
const Store = @import("Store.zig");

pub const std_options: std.Options = .{
    // Every worker thread of the I/O pool lives for the whole process. Only
    // give each one an alternate signal stack when the segfault handler that
    // uses it is enabled; otherwise it is dead weight per thread.
    .signal_stack_size = if (std.debug.default_enable_segfault_handler) (std.Options{}).signal_stack_size else null,
};

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;

    var args = init.minimal.args.iterate();
    const argv0 = args.next() orelse "app";
    const port_arg = args.next() orelse return usage(argv0);
    if (args.next() != null) return usage(argv0);

    const port = std.fmt.parseInt(u16, port_arg, 10) catch 0;
    if (port == 0) {
        std.log.err("invalid port: {s}", .{port_arg});
        return 2;
    }

    var store: Store = .init(init.gpa);
    defer store.deinit();

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{
        .reuse_address = true,
        .kernel_backlog = std.math.maxInt(u16),
    }) catch |err| {
        std.log.err("listen on {f}: {t}", .{ address, err });
        return 1;
    };
    defer listener.deinit(io);

    var server: Server = .{ .io = io, .gpa = init.gpa, .store = &store };
    server.run(&listener) catch |err| {
        std.log.err("accept: {t}", .{err});
        return 1;
    };
    return 0;
}

fn usage(argv0: []const u8) u8 {
    std.log.err("usage: {s} <port>", .{argv0});
    return 2;
}

test {
    _ = @import("http.zig");
    _ = Server;
    _ = Store;
}
