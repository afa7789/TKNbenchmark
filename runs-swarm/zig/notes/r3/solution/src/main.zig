//! notes: a small HTTP notes service backed by SQLite.
//!
//! Usage: NOTES_DB=<path> notes <port>

const std = @import("std");
const Server = @import("Server.zig");
const Store = @import("db/Store.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) std.process.fatal("usage: {s} <port>", .{if (args.len > 0) args[0] else "notes"});
    const port = std.fmt.parseInt(u16, args[1], 10) catch
        std.process.fatal("invalid port: {s}", .{args[1]});

    const db_path = init.environ_map.get("NOTES_DB") orelse
        std.process.fatal("the NOTES_DB environment variable must name the database file", .{});

    var store = Store.open(io, try arena.dupeZ(u8, db_path)) catch
        std.process.fatal("cannot open database {s}", .{db_path});
    defer store.close();

    var server: Server = .{ .gpa = init.gpa, .io = io, .store = &store };
    try server.serve(.{ .ip4 = .loopback(port) });
}

test {
    _ = @import("Server.zig");
    _ = @import("note.zig");
    _ = @import("http/query.zig");
    _ = @import("db/sqlite.zig");
    _ = @import("db/schema.zig");
    _ = @import("db/Store.zig");
    _ = @import("router.zig");
}
