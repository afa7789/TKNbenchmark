//! kvhttp: an in-memory HTTP/1.1 key-value server.
//!
//! Usage: app <port>
//!
//! Listens on 127.0.0.1:<port>, handles one request per connection, and
//! serves each connection on its own concurrent task.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const http = @import("http.zig");
const App = @import("App.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.kvhttp);

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const port = (if (args.len == 2) parsePort(args[1]) else null) orelse {
        try Io.File.stderr().writeStreamingAll(io, "usage: app <port>\n");
        return 2;
    };

    var store: Store = .init(gpa);
    defer store.deinit();
    const app: App = .{ .store = &store };

    const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var server = try address.listen(io, .{ .kernel_backlog = 1024, .reuse_address = true });
    defer server.deinit(io);

    var connections: Io.Group = .init;
    defer connections.cancel(io);

    while (true) {
        const stream = server.accept(io) catch |err| switch (err) {
            error.ConnectionAborted, error.BlockedByFirewall, error.ProtocolFailure => continue,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => {
                log.warn("accept failed: {t}", .{err});
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => |e| return e,
        };
        connections.concurrent(io, serveConnection, .{ app, io, gpa, stream }) catch |err| {
            log.warn("dropping connection: {t}", .{err});
            stream.close(io);
        };
    }
}

fn parsePort(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    for (text) |c| if (!std.ascii.isDigit(c)) return null;
    const port = std.fmt.parseInt(u16, text, 10) catch return null;
    return if (port == 0) null else port;
}

/// After an error response the client may still be sending a request we did
/// not consume. Closing with unread input makes the kernel reset the
/// connection, which can destroy the response in flight, so drain up to this
/// many bytes first.
const max_linger_bytes = 2 * http.max_body_bytes;

fn serveConnection(app: App, io: Io, gpa: Allocator, stream: Io.net.Stream) Io.Cancelable!void {
    defer stream.close(io);

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const recv_buffer = arena.alloc(u8, http.max_header_bytes) catch return;
    var reader = stream.reader(io, recv_buffer);
    var send_buffer: [4096]u8 = undefined;
    var writer = stream.writer(io, &send_buffer);

    const outcome = respond(app, io, arena, &reader.interface) catch |err| switch (err) {
        // The client went away or sent a truncated request; nothing to answer.
        error.EndOfStream => return,
        error.ReadFailed => return if (reader.err) |e| switch (e) {
            error.Canceled => error.Canceled,
            else => {},
        },
        error.Canceled => return error.Canceled,
    };

    outcome.response.write(&writer.interface) catch return;
    writer.interface.flush() catch return;

    if (outcome.unread_input) {
        stream.shutdown(io, .send) catch return;
        _ = reader.interface.discardShort(max_linger_bytes) catch {};
    }
}

const Outcome = struct {
    response: http.Response,
    /// The request was rejected before it was fully read.
    unread_input: bool = false,
};

fn respond(app: App, io: Io, arena: Allocator, reader: *Io.Reader) (Io.Reader.Error || Io.Cancelable)!Outcome {
    const req = http.readRequest(reader, arena) catch |err| switch (err) {
        error.OutOfMemory => return .{ .response = internalError(err), .unread_input = true },
        error.EndOfStream, error.ReadFailed => |e| return e,
        else => |e| return .{ .response = .{ .status = http.statusFor(e) }, .unread_input = true },
    };
    const response = app.handle(io, arena, req) catch |err| switch (err) {
        error.OutOfMemory => internalError(err),
        error.Canceled => return error.Canceled,
    };
    return .{ .response = response };
}

fn internalError(err: anyerror) http.Response {
    log.err("unhandled error while serving request: {t}", .{err});
    return .{ .status = .internal_server_error };
}

test {
    _ = @import("http.zig");
    _ = @import("App.zig");
    _ = @import("Store.zig");
}

test parsePort {
    try std.testing.expectEqual(8080, parsePort("8080"));
    try std.testing.expectEqual(80, parsePort("0080"));
    try std.testing.expectEqual(null, parsePort("0"));
    try std.testing.expectEqual(null, parsePort("65536"));
    try std.testing.expectEqual(null, parsePort("+80"));
    try std.testing.expectEqual(null, parsePort(""));
}
