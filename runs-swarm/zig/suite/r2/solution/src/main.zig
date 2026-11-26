//! Entry point of `app`: dispatches the first command-line argument to the
//! subcommand of the same name. Each subcommand reads standard input and
//! writes standard output; see SPEC.md.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Subcommand = enum {
    wordfreq,
    lru,
    calc,

    /// The entry point of every subcommand.
    const Run = fn (gpa: Allocator, in: *Io.Reader, out: *Io.Writer) anyerror!void;

    fn entryPoint(cmd: Subcommand) *const Run {
        return switch (cmd) {
            .wordfreq => @import("wordfreq").run,
            .lru => @import("lru").run,
            .calc => @import("calc").run,
        };
    }
};

const usage =
    \\usage: app <command>
    \\
    \\commands:
    \\  wordfreq  print the 10 most frequent words of standard input
    \\  lru       simulate an LRU cache driven by standard input
    \\  calc      evaluate one integer expression per line of standard input
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var args = init.minimal.args.iterate();
    _ = args.skip(); // program name
    const name = args.next() orelse fatal(io, "missing command", .{});
    const cmd = std.meta.stringToEnum(Subcommand, name) orelse
        fatal(io, "unknown command '{s}'", .{name});

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);

    cmd.entryPoint()(init.gpa, &stdin_reader.interface, &stdout_writer.interface) catch |err| switch (err) {
        // Surface the underlying I/O error rather than the generic one.
        error.ReadFailed => return stdin_reader.err.?,
        error.WriteFailed => return stdout_writer.err.?,
        else => |e| return e,
    };
    stdout_writer.interface.flush() catch return stdout_writer.err.?;
}

fn fatal(io: Io, comptime fmt: []const u8, args: anytype) noreturn {
    var buffer: [256]u8 = undefined;
    var stderr_writer = Io.File.stderr().writerStreaming(io, &buffer);
    const w = &stderr_writer.interface;
    w.print("app: " ++ fmt ++ "\n\n" ++ usage, args) catch {};
    w.flush() catch {};
    std.process.exit(2);
}

test {
    std.testing.refAllDecls(@This());
}
