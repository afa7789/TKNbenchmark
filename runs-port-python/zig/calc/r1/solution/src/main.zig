//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value,
//! or `error` for syntax errors, division by zero, and 64-bit overflow.
//! Blank lines (empty or only spaces/tabs) produce no output.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const blank = " \t";

pub const EvalError = error{
    InvalidCharacter,
    ExpectedOperand,
    ExpectedOperator,
    UnbalancedParen,
    LiteralOutOfRange,
    DivisionByZero,
    Overflow,
};

pub const Error = EvalError || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    lparen,

    /// Binding strength used by the shunting-yard reduction.
    /// `(` is a barrier and never reduced by an operator.
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

fn applyBinary(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => {
            if (b == 0) return error.DivisionByZero;
            if (a == std.math.minInt(i64) and b == -1) return error.Overflow;
            return @divTrunc(a, b);
        },
        .rem => {
            if (b == 0) return error.DivisionByZero;
            // The remainder always fits: minInt(i64) % -1 == 0.
            if (b == -1) return 0;
            return @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

/// Reusable evaluator. Its operand and operator stacks are retained between
/// calls so that evaluating many lines does not reallocate.
///
/// Uses an operator-precedence (shunting-yard) algorithm rather than
/// recursion so that deeply nested input cannot exhaust the call stack.
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

    fn reduceTop(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        if (op == .neg) {
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try std.math.negate(top.*);
        } else {
            const b = self.values.pop().?;
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try applyBinary(op, top.*, b);
        }
    }

    fn topOp(self: *const Evaluator) ?Op {
        return self.ops.getLastOrNull();
    }

    /// Evaluates a single expression (without its trailing newline).
    pub fn evaluate(self: *Evaluator, line: []const u8) Error!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        const end = std.mem.trimEnd(u8, line, blank).len;
        var pos: usize = 0;
        var expect_operand = true;

        while (pos < end) {
            const c = line[pos];
            switch (c) {
                ' ', '\t' => {
                    pos += 1;
                    continue;
                },
                '0'...'9' => {
                    if (!expect_operand) return error.ExpectedOperator;
                    const start = pos;
                    while (pos < end and std.ascii.isDigit(line[pos])) pos += 1;
                    const value = std.fmt.parseUnsigned(i64, line[start..pos], 10) catch |err| switch (err) {
                        error.Overflow => return error.LiteralOutOfRange,
                        error.InvalidCharacter => unreachable,
                    };
                    try self.values.append(self.gpa, value);
                    expect_operand = false;
                    continue;
                },
                else => {},
            }
            pos += 1;

            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    '+', '*', '/', '%', ')' => return error.ExpectedOperand,
                    else => return error.InvalidCharacter,
                }
            } else if (c == ')') {
                while (self.topOp()) |top| {
                    if (top == .lparen) break;
                    try self.reduceTop();
                } else return error.UnbalancedParen;
                _ = self.ops.pop();
            } else if (Op.fromBinary(c)) |op| {
                // Left-associative: reduce operators of equal or higher precedence.
                while (self.topOp()) |top| {
                    if (top.precedence() < op.precedence()) break;
                    try self.reduceTop();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else if (c == '(') {
                return error.ExpectedOperator;
            } else {
                return error.InvalidCharacter;
            }
        }

        if (expect_operand) return error.ExpectedOperand;
        while (self.topOp()) |top| {
            if (top == .lparen) return error.UnbalancedParen;
            try self.reduceTop();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }
};

fn isBlank(line: []const u8) bool {
    return std.mem.trimStart(u8, line, blank).len == 0;
}

/// Evaluates every line of `input`, writing one result per non-blank line.
pub fn process(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlank(line)) continue;
        if (evaluator.evaluate(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            else => try out.writeAll("error\n"),
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    try process(gpa, input, &stdout.interface);
    try stdout.interface.flush();
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try process(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n", "7\n-3\nerror\nerror\n");
}

test "division and remainder" {
    try expectOutput("7 / 2\n-7 % 3\n7 % -3\n0 / 5\n1 / 0\n5 % 0\n", "3\n-1\n1\n0\nerror\nerror\n");
}

test "overflow edges" {
    try expectOutput(
        "(-9223372036854775807 - 1) % -1\n(-9223372036854775807 - 1) / -1\n-(-9223372036854775807 - 1)\n" ++
            "9223372036854775808\n-9223372036854775808\n3037000500 * 3037000500\n",
        "0\nerror\nerror\nerror\nerror\nerror\n",
    );
}

test "syntax errors and blanks" {
    try expectOutput("1 +\nabc\n()\n1 2\n+1\n\n  42  \n\t\n1+1\n)(\n2(3)\n1\r\n", "error\nerror\nerror\nerror\nerror\n42\n2\nerror\nerror\nerror\n");
}

test "unary minus" {
    try expectOutput("--5\n2 * -3\n1 - -2\n-(2 + 3)\n- 2 * 3\n", "5\n-6\n3\n-5\n-6\n");
}
