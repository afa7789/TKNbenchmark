//! 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from stdin and prints its value or `error`.
//! Lines are split on `\n` only; blank lines (only spaces/tabs) print nothing.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);

    try run(init.gpa, &stdin.interface, &stdout.interface);
    try stdout.interface.flush();
}

/// Evaluates every line of `in`, writing one result line per non-blank line.
pub fn run(gpa: Allocator, in: *Io.Reader, out: *Io.Writer) !void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    while (true) {
        if (in.bufferedLen() == 0) {
            in.fillMore() catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
        }
        for (in.buffered()) |c| {
            if (c == '\n') {
                try emit(&evaluator, out);
            } else {
                try evaluator.feed(c);
            }
        }
        in.tossBuffered();
    }

    // A final line without a trailing newline is still evaluated.
    if (!evaluator.isPristine()) try emit(&evaluator, out);
}

fn emit(evaluator: *Evaluator, out: *Io.Writer) !void {
    switch (try evaluator.finish()) {
        .blank => {},
        .value => |v| try out.print("{d}\n", .{v}),
        .failure => try out.writeAll("error\n"),
    }
}

pub const EvalError = error{ Syntax, DivisionByZero, Overflow };

pub const Outcome = union(enum) {
    blank,
    value: i64,
    failure: EvalError,
};

/// Streaming operator-precedence evaluator for a single line at a time.
///
/// Bytes are fed one by one; `finish` yields the line's outcome and resets
/// the evaluator for the next line. Evaluation uses explicit stacks, so
/// nesting depth is bounded only by available memory.
pub const Evaluator = struct {
    gpa: Allocator,
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,
    /// Whether the next token must be an operand (number, `(` or unary `-`).
    expect_operand: bool = true,
    /// Accumulator for the number literal currently being lexed, if any.
    literal: ?i64 = null,
    /// First error seen on this line; the remainder of the line is ignored.
    failure: ?EvalError = null,
    /// Whether any non-blank byte has been seen on this line.
    seen_token: bool = false,
    /// Whether any byte at all has been fed on this line.
    seen_byte: bool = false,

    const Op = enum {
        lparen,
        add,
        sub,
        mul,
        div,
        rem,
        neg,

        fn precedence(op: Op) u2 {
            return switch (op) {
                .lparen => 0,
                .add, .sub => 1,
                .mul, .div, .rem => 2,
                .neg => 3,
            };
        }

        fn fromBinary(c: u8) ?Op {
            return switch (c) {
                '+' => .add,
                '-' => .sub,
                '*' => .mul,
                '/' => .div,
                '%' => .rem,
                else => null,
            };
        }
    };

    pub fn init(gpa: Allocator) Evaluator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Evaluator) void {
        self.values.deinit(self.gpa);
        self.ops.deinit(self.gpa);
        self.* = undefined;
    }

    /// True when no byte has been fed since the last `finish`.
    pub fn isPristine(self: *const Evaluator) bool {
        return !self.seen_byte;
    }

    /// Feeds one byte of the current line (never `\n`).
    pub fn feed(self: *Evaluator, c: u8) Allocator.Error!void {
        self.seen_byte = true;
        if (c != ' ' and c != '\t') self.seen_token = true;
        if (self.failure != null) return;
        self.step(c) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            else => |e| self.failure = e,
        };
    }

    /// Completes the current line, returns its outcome and resets state.
    pub fn finish(self: *Evaluator) Allocator.Error!Outcome {
        defer self.reset();
        if (!self.seen_token) return .blank;
        if (self.failure) |e| return .{ .failure = e };
        const v = self.complete() catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            else => |e| return .{ .failure = e },
        };
        return .{ .value = v };
    }

    fn reset(self: *Evaluator) void {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();
        self.* = .{ .gpa = self.gpa, .values = self.values, .ops = self.ops };
    }

    fn step(self: *Evaluator, c: u8) (EvalError || Allocator.Error)!void {
        if (self.literal) |acc| {
            if (std.ascii.isDigit(c)) {
                self.literal = try appendDigit(acc, c);
                return;
            }
            try self.endLiteral();
        }

        switch (c) {
            ' ', '\t' => {},
            '0'...'9' => {
                if (!self.expect_operand) return error.Syntax;
                self.literal = c - '0';
            },
            '(' => {
                if (!self.expect_operand) return error.Syntax;
                try self.ops.append(self.gpa, .lparen);
            },
            ')' => {
                if (self.expect_operand) return error.Syntax;
                while (self.ops.pop()) |op| {
                    if (op == .lparen) break;
                    try self.apply(op);
                } else return error.Syntax;
            },
            '-' => if (self.expect_operand) {
                try self.ops.append(self.gpa, .neg);
            } else {
                try self.pushBinary(.sub);
            },
            else => {
                const op = Op.fromBinary(c) orelse return error.Syntax;
                if (self.expect_operand) return error.Syntax;
                try self.pushBinary(op);
            },
        }
    }

    fn endLiteral(self: *Evaluator) Allocator.Error!void {
        try self.values.append(self.gpa, self.literal.?);
        self.literal = null;
        self.expect_operand = false;
    }

    /// Reduces pending operators of equal or higher precedence (all binary
    /// operators are left-associative), then pushes `op`.
    fn pushBinary(self: *Evaluator, op: Op) (EvalError || Allocator.Error)!void {
        try self.reduceWhile(op.precedence());
        try self.ops.append(self.gpa, op);
        self.expect_operand = true;
    }

    fn reduceWhile(self: *Evaluator, min_precedence: u2) EvalError!void {
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen or top.precedence() < min_precedence) break;
            _ = self.ops.pop();
            try self.apply(top);
        }
    }

    fn complete(self: *Evaluator) (EvalError || Allocator.Error)!i64 {
        if (self.literal != null) try self.endLiteral();
        if (self.expect_operand) return error.Syntax;
        while (self.ops.pop()) |op| {
            if (op == .lparen) return error.Syntax;
            try self.apply(op);
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    fn apply(self: *Evaluator, op: Op) EvalError!void {
        if (op == .neg) {
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try negate(top.*);
            return;
        }
        const rhs = self.values.pop().?;
        const lhs = &self.values.items[self.values.items.len - 1];
        lhs.* = try binary(op, lhs.*, rhs);
    }

    fn binary(op: Op, a: i64, b: i64) EvalError!i64 {
        return switch (op) {
            .add => std.math.add(i64, a, b),
            .sub => std.math.sub(i64, a, b),
            .mul => std.math.mul(i64, a, b),
            .div => divTrunc(a, b),
            .rem => remTrunc(a, b),
            .neg, .lparen => unreachable,
        };
    }
};

fn appendDigit(acc: i64, c: u8) EvalError!i64 {
    const shifted = try std.math.mul(i64, acc, 10);
    return std.math.add(i64, shifted, c - '0');
}

fn negate(a: i64) EvalError!i64 {
    return std.math.negate(a);
}

fn divTrunc(a: i64, b: i64) EvalError!i64 {
    if (b == 0) return error.DivisionByZero;
    if (a == std.math.minInt(i64) and b == -1) return error.Overflow;
    return @divTrunc(a, b);
}

/// Remainder of truncating division; its sign follows the dividend.
fn remTrunc(a: i64, b: i64) EvalError!i64 {
    if (b == 0) return error.DivisionByZero;
    // The exact remainder of MIN / -1 is 0; avoid the overflowing division.
    if (b == -1) return 0;
    return @rem(a, b);
}

// ---------------------------------------------------------------------------
// Tests

fn evalLine(line: []const u8) !Outcome {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    for (line) |c| try e.feed(c);
    return e.finish();
}

fn expectValue(expected: i64, line: []const u8) !void {
    try std.testing.expectEqual(Outcome{ .value = expected }, try evalLine(line));
}

fn expectFailure(line: []const u8) !void {
    try std.testing.expect(try evalLine(line) == .failure);
}

test "arithmetic and precedence" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-4, "-2 * 2");
    try expectValue(42, "  42  ");
    try expectValue(1, "0001");
}

test "64-bit boundaries" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure("9223372036854775808");
    try expectFailure("-9223372036854775808");
    try expectFailure("9223372036854775807 + 1");
    try expectFailure("(-9223372036854775807 - 1) / -1");
    try expectFailure("-(-9223372036854775807 - 1)");
    try expectFailure("3037000500 * 3037000500");
}

test "errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "1 / 0", "5 % 0", "1\r", "(1)(2)", "-", "1 - - " }) |line| {
        try expectFailure(line);
    }
}

test "blank lines" {
    try std.testing.expectEqual(Outcome.blank, try evalLine(""));
    try std.testing.expectEqual(Outcome.blank, try evalLine(" \t "));
}

test "run over a stream" {
    var in: Io.Reader = .fixed("1 + 2 * 3\n-7 / 2\n\n(1 + 2\n9223372036854775807 + 1\n 4");
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings("7\n-3\nerror\nerror\n4\n", out.written());
}
