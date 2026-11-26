//! `app`: three independent stdin-to-stdout tools selected by the first argument.

const std = @import("std");
const Io = std.Io;

const wordfreq = @import("wordfreq.zig");
const lru = @import("lru.zig");
const calc = @import("calc.zig");

const Command = enum { wordfreq, lru, calc };

const usage = "usage: app <wordfreq|lru|calc> < input\n";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) fatalUsage(io);
    const command = std.meta.stringToEnum(Command, args[1]) orelse fatalUsage(io);

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader: Io.File.Reader = .initStreaming(.stdin(), io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;

    switch (command) {
        .wordfreq => try wordfreq.run(gpa, input, out),
        .lru => try lru.run(gpa, input, out),
        .calc => try calc.run(gpa, input, out),
    }
    try out.flush();
}

fn fatalUsage(io: Io) noreturn {
    Io.File.stderr().writeStreamingAll(io, usage) catch {};
    std.process.exit(2);
}

test {
    std.testing.refAllDecls(@This());
    _ = wordfreq;
    _ = lru;
    _ = calc;
}
