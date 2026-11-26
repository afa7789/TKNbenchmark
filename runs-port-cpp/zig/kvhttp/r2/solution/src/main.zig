const std = @import("std");

const http = @import("http.zig");
const KvStore = @import("KvStore.zig");
const routes = @import("routes.zig");
const Server = @import("Server.zig");

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.log.err("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
        return 2;
    }
    const port = http.parseUnsigned(u16, args[1], 10) catch 0;
    if (port == 0) {
        std.log.err("invalid port: {s}", .{args[1]});
        return 2;
    }

    var store: KvStore = .init(gpa);
    defer store.deinit();

    var server = Server.listen(gpa, io, .{ .port = port }, .{
        .context = &store,
        .handleFn = handle,
    }) catch |err| {
        std.log.err("listen on 127.0.0.1:{d}: {t}", .{ port, err });
        return 1;
    };
    defer server.deinit();

    server.run() catch {};
    return 0;
}

fn handle(context: *anyopaque, io: std.Io, arena: std.mem.Allocator, request: http.Request) Server.Handler.HandlerError!http.Response {
    const store: *KvStore = @ptrCast(@alignCast(context));
    return routes.route(store, io, arena, request);
}

test {
    _ = http;
    _ = KvStore;
    _ = routes;
    _ = Server;
}
