//! `app`: a small suite of stdin-to-stdout tools selected by the first argument.

const std = @import("std");
const wordfreq = @import("wordfreq.zig");
const lru = @import("lru.zig");
const calc = @import("calc.zig");

const Command = enum { wordfreq, lru, calc };

const usage = "usage: app <wordfreq|lru|calc> < input\n";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.next(); // program name
    const name = args.next() orelse fatal(io, usage);
    const command = std.meta.stringToEnum(Command, name) orelse fatal(io, usage);

    const input = try readStdin(io, gpa);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;

    switch (command) {
        .wordfreq => try wordfreq.run(gpa, input, out),
        .lru => try lru.run(gpa, input, out),
        .calc => try calc.run(gpa, input, out),
    }
    try out.flush();
}

fn readStdin(io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    return stdin.interface.allocRemaining(gpa, .unlimited);
}

fn fatal(io: std.Io, msg: []const u8) noreturn {
    std.Io.File.stderr().writeStreamingAll(io, msg) catch {};
    std.process.exit(2);
}

test {
    std.testing.refAllDecls(@This());
    _ = wordfreq;
    _ = lru;
    _ = calc;
}
