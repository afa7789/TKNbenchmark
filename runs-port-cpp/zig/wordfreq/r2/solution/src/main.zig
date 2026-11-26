//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Output is
//! `<count> <word>` per line, ordered by count descending, then word ascending.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;
const read_buffer_size = 1 << 16;

const WordCounts = std.StringHashMapUnmanaged(u64);

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks strictly before `b`.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Accumulates word counts. Keys are owned by `arena`; the map itself by `gpa`.
const Counter = struct {
    gpa: Allocator,
    arena: Allocator,
    counts: WordCounts = .empty,

    fn deinit(self: *Counter) void {
        self.counts.deinit(self.gpa);
    }

    fn add(self: *Counter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = try self.arena.dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }

    /// Streams `reader` to the end, counting lowercase words. A word may
    /// straddle buffer refills, so the in-progress word is carried in `current`.
    fn countAll(self: *Counter, reader: *Io.Reader) !void {
        var current: std.ArrayList(u8) = .empty;
        defer current.deinit(self.gpa);

        while (true) {
            reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
            const chunk = reader.buffered();
            var i: usize = 0;
            while (i < chunk.len) {
                if (!std.ascii.isAlphabetic(chunk[i])) {
                    if (current.items.len != 0) {
                        try self.add(current.items);
                        current.clearRetainingCapacity();
                    }
                    i += 1;
                    continue;
                }
                const start = i;
                while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) i += 1;
                const run = chunk[start..i];
                if (i < chunk.len and current.items.len == 0) {
                    // Whole word lies inside this chunk: lowercase in place and count.
                    lowerInPlace(run);
                    try self.add(run);
                } else {
                    const old_len = current.items.len;
                    try current.appendSlice(self.gpa, run);
                    lowerInPlace(current.items[old_len..]);
                }
            }
            reader.tossBuffered();
        }
        if (current.items.len != 0) try self.add(current.items);
    }

    /// Returns up to `limit` highest-ranked entries, best first.
    fn top(self: *const Counter, buffer: []Entry) []Entry {
        var len: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |kv| {
            const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == buffer.len and !entry.before(buffer[len - 1])) continue;
            // Insertion into a small sorted array, dropping the last if full.
            var pos = if (len < buffer.len) len else len - 1;
            while (pos > 0 and entry.before(buffer[pos - 1])) : (pos -= 1) {
                buffer[pos] = buffer[pos - 1];
            }
            buffer[pos] = entry;
            if (len < buffer.len) len += 1;
        }
        return buffer[0..len];
    }
};

fn lowerInPlace(bytes: []u8) void {
    for (bytes) |*c| c.* = std.ascii.toLower(c.*);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buffer: [read_buffer_size]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &in_buffer);

    var counter: Counter = .{ .gpa = init.gpa, .arena = init.arena.allocator() };
    defer counter.deinit();
    counter.countAll(&stdin_reader.interface) catch |err| switch (err) {
        error.ReadFailed => return stdin_reader.err orelse err,
        else => |e| return e,
    };

    var top_buffer: [top_n]Entry = undefined;
    const ranked = counter.top(&top_buffer);

    var out_buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buffer);
    const out = &stdout_writer.interface;
    for (ranked) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
    out.flush() catch return stdout_writer.err orelse error.WriteFailed;
}
