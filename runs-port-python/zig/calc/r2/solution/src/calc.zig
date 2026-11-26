//! 64-bit signed integer expression evaluator.
//!
//! Parsing uses an explicit operator stack (shunting-yard) so that deeply
//! nested input cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    /// Any character outside the grammar, unbalanced parentheses, missing operand, ...
    Syntax,
    DivisionByZero,
    /// A literal or intermediate result outside the i64 range.
    Overflow,
} || Allocator.Error;

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
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
            .lparen => unreachable,
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

/// Returns true when `line` holds nothing but spaces and tabs.
pub fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (c != ' ' and c != '\t') return false;
    }
    return true;
}

/// Reusable evaluator; keeps its stacks between calls to avoid reallocating.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Evaluates a single expression.
    pub fn evaluate(self: *Evaluator, gpa: Allocator, line: []const u8) Error!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            switch (c) {
                ' ', '\t' => {
                    i += 1;
                    continue;
                },
                '0'...'9' => {
                    if (!expect_operand) return error.Syntax;
                    const start = i;
                    while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                    try self.values.append(gpa, try parseLiteral(line[start..i]));
                    expect_operand = false;
                    continue;
                },
                else => {},
            }
            i += 1;

            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(gpa, .neg),
                    '(' => try self.ops.append(gpa, .lparen),
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                while (self.ops.pop()) |op| {
                    if (op == .lparen) break;
                    try self.apply(op);
                } else return error.Syntax;
            } else if (Op.fromBinary(c)) |op| {
                const prec = op.precedence();
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen or top.precedence() < prec) break;
                    _ = self.ops.pop();
                    try self.apply(top);
                }
                try self.ops.append(gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.pop()) |op| {
            if (op == .lparen) return error.Syntax;
            try self.apply(op);
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    fn apply(self: *Evaluator, op: Op) Error!void {
        const items = self.values.items;
        if (op == .neg) {
            const top = &items[items.len - 1];
            top.* = std.math.negate(top.*) catch return error.Overflow;
            return;
        }
        const b = self.values.pop().?;
        const a = &items[items.len - 2];
        a.* = try binary(op, a.*, b);
    }
};

fn binary(op: Op, a: i64, b: i64) Error!i64 {
    const math = std.math;
    return switch (op) {
        .add => math.add(i64, a, b) catch error.Overflow,
        .sub => math.sub(i64, a, b) catch error.Overflow,
        .mul => math.mul(i64, a, b) catch error.Overflow,
        .div => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            if (b == -1) break :blk math.negate(a) catch error.Overflow;
            break :blk @divTrunc(a, b);
        },
        // The sign follows the dividend; the remainder never overflows.
        .rem => if (b == 0) error.DivisionByZero else if (b == -1) 0 else @rem(a, b),
        .neg, .lparen => unreachable,
    };
}

fn parseLiteral(digits: []const u8) Error!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = std.math.mul(i64, value, 10) catch return error.Overflow;
        value = std.math.add(i64, value, d - '0') catch return error.Overflow;
    }
    return value;
}

fn testEval(line: []const u8) Error!i64 {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    return ev.evaluate(std.testing.allocator, line);
}

test "arithmetic and precedence" {
    try std.testing.expectEqual(7, try testEval("1 + 2 * 3"));
    try std.testing.expectEqual(9, try testEval("(1 + 2) * 3"));
    try std.testing.expectEqual(5, try testEval("1 + 2 * 3 - 4 / 2 % 3"));
    try std.testing.expectEqual(3, try testEval("10 - 4 - 3"));
    try std.testing.expectEqual(-3, try testEval("-7 / 2"));
    try std.testing.expectEqual(-1, try testEval("-7 % 3"));
    try std.testing.expectEqual(1, try testEval("7 % -3"));
    try std.testing.expectEqual(5, try testEval("--5"));
    try std.testing.expectEqual(-5, try testEval("-(2 + 3)"));
    try std.testing.expectEqual(1, try testEval("\t000000000000000000000000001 "));
}

test "64-bit limits" {
    try std.testing.expectEqual(0, try testEval("(-9223372036854775807 - 1) % -1"));
    try std.testing.expectEqual(std.math.minInt(i64), try testEval("-9223372036854775807 - 1"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775808"));
    try std.testing.expectError(error.Overflow, testEval("-9223372036854775808"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775807 + 1"));
    try std.testing.expectError(error.Overflow, testEval("(-9223372036854775807 - 1) / -1"));
    try std.testing.expectError(error.Overflow, testEval("-(-9223372036854775807 - 1)"));
    try std.testing.expectError(error.Overflow, testEval("3037000500 * 3037000500"));
}

test "errors" {
    try std.testing.expectError(error.DivisionByZero, testEval("1 / 0"));
    try std.testing.expectError(error.DivisionByZero, testEval("5 % 0"));
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1 (2)", "1\r", "-" }) |line| {
        try std.testing.expectError(error.Syntax, testEval(line));
    }
}
