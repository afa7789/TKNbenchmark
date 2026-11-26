//! kvhttp: a minimal in-memory HTTP/1.1 key-value server (see SPEC.md).
//!
//! Usage: kvhttp <port>
//! Listens on 127.0.0.1:<port>; each connection serves a single request.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const net = std.Io.net;

const http = @import("http.zig");
const routes = @import("routes.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

pub const std_options: std.Options = .{ .log_level = .warn };

const read_buffer_size = http.max_head_size;
const write_buffer_size = 16 * 1024;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port = parsePort(args) orelse {
        const name = if (args.len > 0) std.fs.path.basename(args[0]) else "kvhttp";
        std.debug.print("usage: {s} <port>\n", .{name});
        return 2;
    };

    var store: Store = .init(gpa);
    defer store.deinit();

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = try address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 });
    defer server.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted, error.ProtocolFailure => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                log.warn("accept failed: {t}", .{err});
                // Back off briefly so in-flight connections can finish and release resources.
                io.sleep(.fromMilliseconds(10), .awake) catch {};
                continue;
            },
            else => return err,
        };
        group.concurrent(io, serveConnection, .{ io, gpa, &store, stream }) catch |err| {
            log.warn("cannot spawn connection handler ({t}); serving inline", .{err});
            serveConnection(io, gpa, &store, stream);
        };
    }
}

fn parsePort(args: []const [:0]const u8) ?u16 {
    if (args.len != 2) return null;
    const text = args[1];
    if (text.len == 0) return null;
    for (text) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseInt(u16, text, 10) catch null;
}

fn serveConnection(io: Io, gpa: Allocator, store: *Store, stream: net.Stream) void {
    defer stream.close(io);
    handleConnection(io, gpa, store, stream) catch |err| switch (err) {
        error.ReadFailed, error.WriteFailed => {},
        error.OutOfMemory => log.err("out of memory while serving request", .{}),
    };
}

const ConnectionError = error{ ReadFailed, WriteFailed, OutOfMemory };

fn handleConnection(io: Io, gpa: Allocator, store: *Store, stream: net.Stream) ConnectionError!void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const read_buffer = try arena.alloc(u8, read_buffer_size);
    const write_buffer = try arena.alloc(u8, write_buffer_size);
    var reader = stream.reader(io, read_buffer);
    var writer = stream.writer(io, write_buffer);

    var response: http.Response = undefined;
    var owned_body: []const u8 = "";
    defer gpa.free(owned_body);

    if (http.readRequest(arena, gpa, &reader.interface)) |maybe_request| {
        const request = maybe_request orelse return;
        response = routes.handle(store, io, gpa, request) catch |err| switch (err) {
            error.OutOfMemory => .{ .status = .internal_server_error },
        };
        owned_body = response.body;
    } else |err| {
        // A null status means the connection itself failed; nothing can be sent.
        response = .{ .status = http.errorStatus(err) orelse return error.ReadFailed };
    }

    try response.write(&writer.interface);
}

test {
    _ = http;
    _ = routes;
    _ = Store;
}

test parsePort {
    try std.testing.expectEqual(@as(?u16, 8080), parsePort(&.{ "app", "8080" }));
    try std.testing.expectEqual(@as(?u16, null), parsePort(&.{"app"}));
    try std.testing.expectEqual(@as(?u16, null), parsePort(&.{ "app", "-1" }));
    try std.testing.expectEqual(@as(?u16, null), parsePort(&.{ "app", "70000" }));
}
