//! notes: a small notes store over HTTP, backed by SQLite.
//!
//! Usage: NOTES_DB=<path> app <port>

const std = @import("std");
const Server = @import("Server.zig");
const Store = @import("Store.zig");

const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        std.process.fatal("usage: {s} <port>", .{if (args.len > 0) args[0] else "app"});
    }
    const port = std.fmt.parseInt(u16, args[1], 10) catch
        std.process.fatal("invalid port: {s}", .{args[1]});

    const db_path = init.environ_map.get("NOTES_DB") orelse
        std.process.fatal("the NOTES_DB environment variable must name the database file", .{});

    var store = Store.open(init.io, try arena.dupeZ(u8, db_path)) catch |err|
        std.process.fatal("cannot open database {s}: {t}", .{ db_path, err });
    defer store.close();

    var server: Server = .{ .gpa = init.gpa, .io = init.io, .store = &store, .options = .{} };
    try server.serve(.{ .ip4 = .loopback(port) });
}

test {
    _ = @import("sqlite.zig");
    _ = @import("Store.zig");
    _ = @import("model.zig");
    _ = @import("web.zig");
    _ = @import("router.zig");
    _ = @import("Server.zig");
    _ = @import("api/health.zig");
    _ = @import("api/notes.zig");
    _ = @import("api/crud.zig");
    _ = @import("api/list.zig");
    _ = @import("api/stats.zig");
    _ = @import("store/notes.zig");
    _ = @import("store/crud.zig");
    _ = @import("store/list.zig");
    _ = @import("store/stats.zig");
}
