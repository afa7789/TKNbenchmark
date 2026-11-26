//! Entry point of `./app`: dispatches the first argument to a subcommand.

const std = @import("std");

const wordfreq = @import("wordfreq");
const lru = @import("lru");
const calc = @import("calc");

const Subcommand = enum { wordfreq, lru, calc };

const usage = "usage: app <wordfreq|lru|calc>\n";

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.skip(); // program name

    const name = args.next() orelse {
        std.debug.print(usage, .{});
        std.process.exit(2);
    };
    const subcommand = std.meta.stringToEnum(Subcommand, name) orelse {
        std.debug.print("app: unknown subcommand '{s}'\n" ++ usage, .{name});
        std.process.exit(2);
    };

    switch (subcommand) {
        .wordfreq => try wordfreq.run(init),
        .lru => try lru.run(init),
        .calc => try calc.run(init),
    }
}

test {
    std.testing.refAllDecls(@This());
}
