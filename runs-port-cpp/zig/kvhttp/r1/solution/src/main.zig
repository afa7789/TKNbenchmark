//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>   (listens on 127.0.0.1:<port>)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = std.Io.net;
const posix = std.posix;

const http = @import("http.zig");
const KvStore = @import("KvStore.zig");
const Router = @import("Router.zig");

const log = std.log.scoped(.kvhttp);

const limits: http.Limits = .{};

/// Idle/stalled clients are dropped after this long so they cannot pin a
/// thread forever.
const socket_timeout_seconds = 30;

const Server = struct {
    io: Io,
    gpa: Allocator,
    router: Router,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.print("usage: {s} <port>\n", .{args[0]});
        std.process.exit(2);
    }
    const port = parsePort(args[1]) orelse {
        std.debug.print("invalid port: {s}\n", .{args[1]});
        std.process.exit(2);
    };

    const address: net.IpAddress = .{ .ip4 = .loopback(port) };
    var listener = address.listen(io, .{ .reuse_address = true }) catch |err| {
        std.debug.print("fatal: listen on port {d}: {t}\n", .{ port, err });
        std.process.exit(1);
    };
    defer listener.deinit(io);

    var store: KvStore = .init(gpa);
    defer store.deinit();
    const server: Server = .{ .io = io, .gpa = gpa, .router = .{ .store = &store } };

    // One task per connection: connections are short-lived and the required
    // concurrency is modest.
    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.ConnectionAborted, error.WouldBlock => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => |e| return e,
        };
        connections.concurrent(io, serveConnection, .{ &server, stream }) catch |err| {
            log.err("failed to spawn handler: {t}", .{err});
            stream.close(io);
        };
    }
}

fn serveConnection(server: *const Server, stream: net.Stream) void {
    const io = server.io;
    const gpa = server.gpa;
    defer stream.close(io);
    configureClient(stream.socket.handle);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    respond(server, stream, arena) catch |err| switch (err) {
        error.OutOfMemory => log.err("out of memory while serving a request", .{}),
    };
    // Half-close so the client reads the full response before the FIN.
    stream.shutdown(io, .send) catch {};
}

fn respond(server: *const Server, stream: net.Stream, arena: Allocator) Allocator.Error!void {
    const io = server.io;
    const gpa = server.gpa;

    const read_buffer = try arena.alloc(u8, limits.readBufferLen());
    var reader = stream.reader(io, read_buffer);
    var write_buffer: [4096]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);

    const reply: Router.Reply = reply: switch (try http.readRequest(&reader.interface, arena, gpa, limits)) {
        .closed => return,
        .reject => |status| break :reply .{ .response = .empty(status) },
        .request => |request| {
            var req = request;
            defer gpa.free(req.body);
            break :reply server.router.handle(io, arena, &req) catch
                .{ .response = .empty(.internal_server_error) };
        },
    };
    defer reply.release(gpa);

    http.writeResponse(&writer.interface, reply.response) catch {};
}

fn configureClient(fd: net.Socket.Handle) void {
    const one = std.mem.toBytes(@as(c_int, 1));
    posix.setsockopt(fd, posix.IPPROTO.TCP, posix.TCP.NODELAY, &one) catch {};

    // When these fire, std.Io maps the resulting EAGAIN to error.Unexpected
    // and the connection is dropped.
    const timeout: posix.timeval = .{ .sec = socket_timeout_seconds, .usec = 0 };
    const timeout_bytes = std.mem.asBytes(&timeout);
    posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.RCVTIMEO, timeout_bytes) catch {};
    posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.SNDTIMEO, timeout_bytes) catch {};
}

fn parsePort(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    for (text) |c| if (!std.ascii.isDigit(c)) return null;
    const port = std.fmt.parseUnsigned(u16, text, 10) catch return null;
    return if (port == 0) null else port;
}

test parsePort {
    try std.testing.expectEqual(@as(?u16, 8080), parsePort("8080"));
    try std.testing.expectEqual(@as(?u16, 65535), parsePort("65535"));
    try std.testing.expectEqual(@as(?u16, null), parsePort("0"));
    try std.testing.expectEqual(@as(?u16, null), parsePort("65536"));
    try std.testing.expectEqual(@as(?u16, null), parsePort("+80"));
    try std.testing.expectEqual(@as(?u16, null), parsePort(""));
}

test {
    _ = http;
    _ = KvStore;
    _ = Router;
}
