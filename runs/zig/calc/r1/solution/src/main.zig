//! calc: evaluates one 64-bit signed integer expression per input line.
//!
//! The parser is an iterative operator-precedence (shunting-yard) evaluator
//! with explicit stacks, so arbitrarily deep nesting cannot overflow the
//! native call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EvalError = error{ Syntax, DivisionByZero, Overflow } || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    lparen,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
        };
    }
};

/// Reusable evaluator; keeps its stacks allocated across lines.
pub const Evaluator = struct {
    gpa: Allocator,
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn init(gpa: Allocator) Evaluator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Evaluator) void {
        self.values.deinit(self.gpa);
        self.ops.deinit(self.gpa);
        self.* = undefined;
    }

    /// Evaluates `line`. Returns null if the line is blank.
    pub fn eval(self: *Evaluator, line: []const u8) EvalError!?i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var seen_token = false;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (c == ' ' or c == '\t') {
                i += 1;
                continue;
            }
            seen_token = true;
            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        const n = std.fmt.parseInt(i64, line[start..i], 10) catch |err| switch (err) {
                            error.Overflow => return error.Overflow,
                            error.InvalidCharacter => unreachable,
                        };
                        try self.values.append(self.gpa, n);
                        expect_operand = false;
                        continue;
                    },
                    else => return error.Syntax,
                }
            } else {
                const op: Op = switch (c) {
                    '+' => .add,
                    '-' => .sub,
                    '*' => .mul,
                    '/' => .div,
                    '%' => .rem,
                    ')' => {
                        try self.reduceWhile(1);
                        if (self.ops.pop() == null) return error.Syntax;
                        i += 1;
                        continue;
                    },
                    else => return error.Syntax,
                };
                // Left associativity: reduce operators of equal or higher precedence.
                try self.reduceWhile(op.precedence());
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            }
            i += 1;
        }

        if (!seen_token) return null;
        if (expect_operand) return error.Syntax;
        try self.reduceWhile(1);
        if (self.ops.items.len != 0) return error.Syntax; // unclosed '('
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    /// Applies stacked operators while their precedence is at least `min_prec`.
    /// Stops at (without popping) a '(' since its precedence is 0.
    fn reduceWhile(self: *Evaluator, min_prec: u8) EvalError!void {
        while (self.ops.items.len > 0) {
            const op = self.ops.items[self.ops.items.len - 1];
            if (op.precedence() < min_prec) return;
            _ = self.ops.pop();
            try self.apply(op);
        }
    }

    fn apply(self: *Evaluator, op: Op) EvalError!void {
        const vals = &self.values;
        if (op == .neg) {
            const top = &vals.items[vals.items.len - 1];
            top.* = std.math.negate(top.*) catch return error.Overflow;
            return;
        }
        const rhs = vals.pop().?;
        const lhs = &vals.items[vals.items.len - 1];
        lhs.* = try binary(op, lhs.*, rhs);
    }
};

fn binary(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => if (b == 0)
            error.DivisionByZero
        else if (a == std.math.minInt(i64) and b == -1)
            error.Overflow
        else
            @divTrunc(a, b),
        .rem => if (b == 0)
            error.DivisionByZero
        else if (b == -1)
            0
        else
            @rem(a, b),
        .neg, .lparen => unreachable,
    };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const in = &stdin_reader.interface;

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;

    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    while (true) {
        line.clearRetainingCapacity();
        const len = try in.streamDelimiterEnding(&line.writer, '\n');
        const at_eof = blk: {
            _ = in.takeByte() catch |err| switch (err) {
                error.EndOfStream => break :blk true,
                else => |e| return e,
            };
            break :blk false;
        };
        if (at_eof and len == 0) break;

        if (evaluator.eval(line.written())) |result| {
            if (result) |value| try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
        if (at_eof) break;
    }
    try out.flush();
}

fn expectEval(input: []const u8, expected: EvalError!?i64) !void {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectEqual(expected, e.eval(input));
}

test "arithmetic" {
    try expectEval("1 + 2 * 3", 7);
    try expectEval("-7 / 2", -3);
    try expectEval("-7 % 3", -1);
    try expectEval("7 % -3", 1);
    try expectEval("10 - 4 - 3", 3);
    try expectEval("--5", 5);
    try expectEval("-(2 + 3)", -5);
    try expectEval("(-9223372036854775807 - 1) % -1", 0);
    try expectEval(" \t ", null);
}

test "errors" {
    try expectEval("(1 + 2", error.Syntax);
    try expectEval("1 2", error.Syntax);
    try expectEval("()", error.Syntax);
    try expectEval("+1", error.Syntax);
    try expectEval("1)", error.Syntax);
    try expectEval("1 / 0", error.DivisionByZero);
    try expectEval("9223372036854775807 + 1", error.Overflow);
    try expectEval("9223372036854775808", error.Overflow);
    try expectEval("-(-9223372036854775807 - 1)", error.Overflow);
    try expectEval("(-9223372036854775807 - 1) / -1", error.Overflow);
}
