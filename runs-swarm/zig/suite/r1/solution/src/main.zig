//! Entry point of `app`: dispatches the first argument to a subcommand.

const std = @import("std");

const Subcommand = enum { wordfreq, lru, calc };

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.skip(); // program name

    const name = args.next() orelse usage();
    const subcommand = std.meta.stringToEnum(Subcommand, name) orelse usage();

    switch (subcommand) {
        .wordfreq => try @import("wordfreq").run(init),
        .lru => try @import("lru").run(init),
        .calc => try @import("calc").run(init),
    }
}

fn usage() noreturn {
    std.debug.print("usage: app <wordfreq|lru|calc>\n", .{});
    std.process.exit(2);
}

test {
    _ = @import("wordfreq");
    _ = @import("lru");
    _ = @import("calc");
}
