//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads expressions from standard input, one per line, and prints each
//! value or `error`. Lines that are empty or hold only spaces/tabs print
//! nothing. See SPEC.md for the grammar and semantics.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buf);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    const out = &stdout_writer.interface;

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlank(line)) continue;
        if (evaluator.evaluate(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
    try out.flush();
}

fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (c != ' ' and c != '\t') return false;
    }
    return true;
}

pub const EvalError = error{ Syntax, DivisionByZero, Overflow } || Allocator.Error;

/// Entries of the operator stack.
const Op = enum {
    lparen,
    neg,
    add,
    sub,
    mul,
    div,
    rem,

    fn precedence(op: Op) u8 {
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

/// Iterative operator-precedence (shunting-yard) evaluator, so arbitrarily
/// deep nesting cannot overflow the call stack. The stacks are reused across
/// calls to avoid per-line allocations.
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

    /// Evaluates one expression line.
    pub fn evaluate(self: *Evaluator, line: []const u8) EvalError!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (c == ' ' or c == '\t') {
                i += 1;
                continue;
            }
            if (expect_operand) {
                switch (c) {
                    '0'...'9' => {
                        var j = i;
                        var value: i64 = 0;
                        while (j < line.len and std.ascii.isDigit(line[j])) : (j += 1) {
                            value = try std.math.mul(i64, value, 10);
                            value = try std.math.add(i64, value, line[j] - '0');
                        }
                        try self.values.append(self.gpa, value);
                        i = j;
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen) break;
                    try self.reduceTop();
                } else return error.Syntax;
                _ = self.ops.pop();
            } else if (Op.fromBinary(c)) |op| {
                while (self.ops.getLastOrNull()) |top| {
                    if (top.precedence() < op.precedence()) break;
                    try self.reduceTop();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduceTop();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    /// Pops the top operator and applies it to the value stack. The parser's
    /// operand/operator alternation guarantees enough operands are present.
    fn reduceTop(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        if (op == .neg) {
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try std.math.negate(top.*);
            return;
        }
        const b = self.values.pop().?;
        const a = &self.values.items[self.values.items.len - 1];
        a.* = try applyBinary(op, a.*, b);
    }
};

fn applyBinary(op: Op, a: i64, b: i64) EvalError!i64 {
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
        // The remainder of INT64_MIN / -1 is mathematically 0, not an overflow.
        .rem => if (b == 0) error.DivisionByZero else if (b == -1) 0 else @rem(a, b),
        .lparen, .neg => unreachable,
    };
}

fn evalTest(line: []const u8) EvalError!i64 {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    return e.evaluate(line);
}

test "precedence and associativity" {
    try std.testing.expectEqual(7, try evalTest("1 + 2 * 3"));
    try std.testing.expectEqual(3, try evalTest("10 - 4 - 3"));
    try std.testing.expectEqual(5, try evalTest("1 + 2 * 3 - 4 / 2 % 3"));
    try std.testing.expectEqual(5, try evalTest("--5"));
    try std.testing.expectEqual(-5, try evalTest("-(2 + 3)"));
}

test "division semantics" {
    try std.testing.expectEqual(-3, try evalTest("-7 / 2"));
    try std.testing.expectEqual(-1, try evalTest("-7 % 3"));
    try std.testing.expectEqual(1, try evalTest("7 % -3"));
    try std.testing.expectEqual(0, try evalTest("(-9223372036854775807 - 1) % -1"));
    try std.testing.expectError(error.Overflow, evalTest("(-9223372036854775807 - 1) / -1"));
    try std.testing.expectError(error.DivisionByZero, evalTest("1 / 0"));
}

test "errors" {
    try std.testing.expectError(error.Overflow, evalTest("9223372036854775808"));
    try std.testing.expectError(error.Overflow, evalTest("-9223372036854775808"));
    try std.testing.expectError(error.Syntax, evalTest("(1 + 2"));
    try std.testing.expectError(error.Syntax, evalTest("1 + 2)"));
    try std.testing.expectError(error.Syntax, evalTest("()"));
    try std.testing.expectError(error.Syntax, evalTest("1 2"));
    try std.testing.expectError(error.Syntax, evalTest("+1"));
}
