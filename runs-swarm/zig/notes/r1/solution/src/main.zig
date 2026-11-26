//! notes: a small notes store over HTTP, backed by SQLite.
//!
//! Usage: NOTES_DB=<path> notes <port>

const std = @import("std");
const Server = @import("server.zig").Server;
const Pool = @import("db/Pool.zig");

const log = std.log.scoped(.main);

const usage = "usage: NOTES_DB=<database path> notes <port>";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) fatal("{s}", .{usage});
    const port = std.fmt.parseInt(u16, args[1], 10) catch fatal("invalid port '{s}'\n{s}", .{ args[1], usage });

    const db_path = init.environ_map.get("NOTES_DB") orelse fatal("NOTES_DB is not set\n{s}", .{usage});
    if (db_path.len == 0) fatal("NOTES_DB is empty\n{s}", .{usage});

    var pool = Pool.init(gpa, try arena.dupeZ(u8, db_path), .{}) catch |err|
        fatal("cannot open database '{s}': {t}", .{ db_path, err });
    defer pool.deinit();

    const address = std.Io.net.IpAddress.parseIp4("127.0.0.1", port) catch unreachable;
    var listener = address.listen(io, .{ .reuse_address = true }) catch |err|
        fatal("cannot listen on 127.0.0.1:{d}: {t}", .{ port, err });
    defer listener.deinit(io);
    log.info("listening on http://127.0.0.1:{d}", .{port});

    const server: Server = .{ .io = io, .gpa = gpa, .pool = &pool };
    server.serve(&listener) catch |err| switch (err) {
        error.Canceled => {},
    };
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

test {
    _ = @import("api.zig");
    _ = @import("note.zig");
    _ = @import("router.zig");
    _ = @import("server.zig");
    _ = @import("db/sqlite.zig");
    _ = @import("db/schema.zig");
    _ = @import("db/Pool.zig");
    _ = @import("store/notes.zig");
    _ = @import("handlers/notes.zig");
    _ = @import("handlers/crud.zig");
    _ = @import("handlers/list.zig");
    _ = @import("handlers/stats.zig");
}
