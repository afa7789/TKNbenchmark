//! `app <wordfreq|lru|calc>`: each subcommand reads all of stdin and writes its results to stdout.

const std = @import("std");
const Io = std.Io;

const wordfreq = @import("wordfreq.zig");
const lru = @import("lru.zig");
const calc = @import("calc.zig");

const Command = enum { wordfreq, lru, calc };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Process-lifetime allocations; everything is freed at exit.
    const gpa = init.arena.allocator();

    var args = init.minimal.args.iterate();
    _ = args.next();
    const name = args.next() orelse usage();
    const command = std.meta.stringToEnum(Command, name) orelse usage();

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;

    switch (command) {
        .wordfreq => try wordfreq.run(gpa, input, out),
        .lru => try lru.run(gpa, input, out),
        .calc => try calc.run(gpa, input, out),
    }
    try out.flush();
}

fn usage() noreturn {
    std.debug.print("usage: app <wordfreq|lru|calc>\n", .{});
    std.process.exit(2);
}

test {
    _ = wordfreq;
    _ = lru;
    _ = calc;
}
