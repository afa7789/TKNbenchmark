//! Signed 64-bit integer expression evaluator.
//!
//! Grammar:
//!   expr    := term    (('+' | '-') term)*
//!   term    := unary   (('*' | '/' | '%') unary)*
//!   unary   := '-' unary | primary
//!   primary := NUMBER | '(' expr ')'
//!
//! Parsing is iterative (operator precedence with explicit stacks) so that
//! deeply nested input cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Failures that make a line evaluate to `error`.
pub const CalcError = error{
    Syntax,
    DivisionByZero,
    Overflow,
};

pub const Error = CalcError || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    lparen,

    fn fromByte(c: u8) ?Op {
        return switch (c) {
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            '%' => .rem,
            else => null,
        };
    }

    /// Binding strength of binary operators; unary negation binds tighter
    /// than any binary operator.
    fn precedence(op: Op) u8 {
        return switch (op) {
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
            .lparen => 0,
        };
    }
};

fn applyBinary(op: Op, a: i64, b: i64) CalcError!i64 {
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
            // The exact remainder is always 0 here; avoid the trapping case.
            if (b == -1) return 0;
            return @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

fn isBlankByte(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Returns true if `line` contains only spaces and tabs.
pub fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (!isBlankByte(c)) return false;
    }
    return true;
}

/// Reusable evaluator; keeps its stacks' capacity between calls.
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

    /// Pops the top operator and applies it to the value stack.
    /// The parser guarantees the operands are present.
    fn reduceTop(self: *Evaluator) CalcError!void {
        const op = self.ops.pop().?;
        switch (op) {
            .lparen => unreachable,
            .neg => {
                const top = &self.values.items[self.values.items.len - 1];
                top.* = try std.math.negate(top.*);
            },
            else => {
                const b = self.values.pop().?;
                const top = &self.values.items[self.values.items.len - 1];
                top.* = try applyBinary(op, top.*, b);
            },
        }
    }

    /// Evaluates one expression.
    pub fn evaluate(self: *Evaluator, src: []const u8) Error!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (i < src.len) {
            const c = src[i];
            if (isBlankByte(c)) {
                i += 1;
                continue;
            }

            if (std.ascii.isDigit(c)) {
                if (!expect_operand) return error.Syntax;
                var value: i64 = 0;
                while (i < src.len and std.ascii.isDigit(src[i])) : (i += 1) {
                    value = try std.math.mul(i64, value, 10);
                    value = try std.math.add(i64, value, src[i] - '0');
                }
                try self.values.append(self.gpa, value);
                expect_operand = false;
                continue;
            }

            i += 1;

            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.Syntax,
                }
                continue;
            }

            if (Op.fromByte(c)) |op| {
                const prec = op.precedence();
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen or top.precedence() < prec) break;
                    try self.reduceTop();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else if (c == ')') {
                while (true) {
                    const top = self.ops.getLastOrNull() orelse return error.Syntax;
                    if (top == .lparen) break;
                    try self.reduceTop();
                }
                _ = self.ops.pop();
            } else {
                return error.Syntax;
            }
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduceTop();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }
};

fn expectValue(expected: i64, src: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectEqual(expected, try ev.evaluate(src));
}

fn expectFailure(expected: CalcError, src: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectError(expected, ev.evaluate(src));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(1, "8 / 4 / 2");
}

test "division and remainder" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % 0");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
}

test "overflow" {
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
    try expectValue(9223372036854775807, "0009223372036854775807");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1\r", "-" }) |src| {
        try expectFailure(error.Syntax, src);
    }
}

test "blank lines" {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank(" 1 "));
}
