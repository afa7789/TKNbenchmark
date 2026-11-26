//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app [--host <addr>] <port>
//!
//! One request is handled per connection; every response carries an exact
//! Content-Length (except 204) and the connection is closed afterwards.

const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;

const App = @import("App.zig");
const Store = @import("Store.zig");
const http = @import("http.zig");

const log = std.log.scoped(.kvhttp);

/// Idle connections are dropped after this long without receiving data.
const read_timeout_seconds = 30;
/// After an early error response, at most this much unread request data is
/// drained so the client sees the response instead of a connection reset.
const max_drain_bytes = 4 * http.max_body_bytes;

const Server = struct {
    io: Io,
    gpa: Allocator,
    app: App,

    fn handleConnection(s: *Server, stream: net.Stream) void {
        defer stream.close(s.io);
        s.serveOne(stream) catch |err| switch (err) {
            error.OutOfMemory => log.err("out of memory while handling request", .{}),
            // The peer went away or timed out; there is nobody to answer.
            error.ReadFailed, error.WriteFailed, error.EndOfStream, error.Canceled => {},
        };
    }

    fn serveOne(s: *Server, stream: net.Stream) !void {
        setReceiveTimeout(stream);

        var arena_state: std.heap.ArenaAllocator = .init(s.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        const read_buffer = try arena.alloc(u8, http.max_head_bytes);
        var reader = stream.reader(s.io, read_buffer);
        var write_buffer: [4096]u8 = undefined;
        var writer = stream.writer(s.io, &write_buffer);

        var fully_read = true;
        const response: http.Response = if (http.readRequest(arena, &reader.interface)) |req|
            s.app.handle(s.io, arena, req) catch |err| switch (err) {
                error.Canceled => |e| return e,
                error.OutOfMemory => .{ .status = .internal_server_error },
            }
        else |err| switch (err) {
            error.BadRequest, error.ContentTooLarge, error.HeaderFieldsTooLarge => |e| blk: {
                fully_read = false;
                break :blk .{ .status = http.statusFor(e) };
            },
            error.OutOfMemory => blk: {
                fully_read = false;
                break :blk .{ .status = .internal_server_error };
            },
            error.ReadFailed, error.EndOfStream => |e| return e,
        };

        try response.write(&writer.interface);

        if (!fully_read) {
            // Lingering close: closing with unread input would make the kernel
            // reset the connection, possibly discarding the response.
            stream.shutdown(s.io, .send) catch return;
            var drained: usize = 0;
            while (drained < max_drain_bytes) {
                drained += reader.interface.discard(.limited(max_drain_bytes - drained)) catch break;
            }
        }
    }
};

fn setReceiveTimeout(stream: net.Stream) void {
    const tv: std.posix.timeval = .{ .sec = read_timeout_seconds, .usec = 0 };
    std.posix.setsockopt(
        stream.socket.handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&tv),
    ) catch |err| log.warn("cannot set receive timeout: {t}", .{err});
}

const Options = struct {
    host: []const u8 = "127.0.0.1",
    port: u16,
};

fn usage() noreturn {
    std.debug.print("usage: app [--host HOST] PORT\n", .{});
    std.process.exit(2);
}

fn parseArgs(args: std.process.Args) Options {
    var it = args.iterate();
    _ = it.skip();
    var host: ?[]const u8 = null;
    var port: ?u16 = null;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--host")) {
            host = it.next() orelse usage();
        } else if (std.mem.startsWith(u8, arg, "--host=")) {
            host = arg["--host=".len..];
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            usage();
        } else if (port == null) {
            port = std.fmt.parseUnsigned(u16, arg, 10) catch usage();
        } else {
            usage();
        }
    }
    return .{ .host = host orelse "127.0.0.1", .port = port orelse usage() };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const options = parseArgs(init.minimal.args);

    const address = net.IpAddress.parse(options.host, options.port) catch |err| {
        log.err("invalid host '{s}': {t}", .{ options.host, err });
        std.process.exit(2);
    };
    var listener = address.listen(io, .{ .reuse_address = true, .kernel_backlog = 1024 }) catch |err| {
        log.err("cannot listen on {f}: {t}", .{ address, err });
        std.process.exit(1);
    };
    defer listener.deinit(io);
    log.info("listening on {f}", .{address});

    var store: Store = .init(gpa);
    defer store.deinit();
    var server: Server = .{ .io = io, .gpa = gpa, .app = .{ .store = &store } };

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = listener.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.ConnectionAborted => continue,
            else => {
                log.warn("accept failed: {t}", .{err});
                // Typically descriptor exhaustion; back off instead of spinning.
                io.sleep(.fromMilliseconds(10), .awake) catch |e| return e;
                continue;
            },
        };
        connections.concurrent(io, Server.handleConnection, .{ &server, stream }) catch {
            // No thread available: serve inline rather than dropping the client.
            server.handleConnection(stream);
        };
    }
}

test {
    _ = App;
    _ = Store;
    _ = http;
}
