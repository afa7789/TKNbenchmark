//! 64-bit signed integer expression evaluator.
//!
//! Grammar (blanks may appear between tokens):
//!   expr    := term    (('+' | '-') term)*
//!   term    := unary   (('*' | '/' | '%') unary)*
//!   unary   := '-' unary | primary
//!   primary := NUMBER | '(' expr ')'
//!
//! Parsing uses an operator-precedence (shunting-yard) algorithm with explicit
//! stacks, so deeply nested input cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    Syntax,
    DivisionByZero,
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

fn applyBinary(op: Op, a: i64, b: i64) Error!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => {
            if (b == 0) return error.DivisionByZero;
            if (b == -1) return std.math.negate(a);
            return @divTrunc(a, b);
        },
        .rem => {
            if (b == 0) return error.DivisionByZero;
            // minInt % -1 is mathematically 0; avoid the overflowing division.
            if (b == -1) return 0;
            return @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Returns true if the line is empty or holds only spaces/tabs.
pub fn isBlankLine(line: []const u8) bool {
    for (line) |c| {
        if (!isBlank(c)) return false;
    }
    return true;
}

/// Reusable evaluator; keeps its stacks between calls to avoid reallocating.
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

    /// Evaluates one expression.
    pub fn evaluate(self: *Evaluator, line: []const u8) Error!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (isBlank(c)) {
                i += 1;
                continue;
            }
            if (expect_operand) {
                switch (c) {
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        const value = std.fmt.parseInt(i64, line[start..i], 10) catch |err| switch (err) {
                            error.Overflow => return error.Overflow,
                            error.InvalidCharacter => unreachable,
                        };
                        try self.values.append(self.gpa, value);
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.Syntax,
                }
            } else if (Op.fromBinary(c)) |op| {
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen or top.precedence() < op.precedence()) break;
                    try self.reduce();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else if (c == ')') {
                while (true) {
                    const top = self.ops.getLastOrNull() orelse return error.Syntax;
                    if (top == .lparen) break;
                    try self.reduce();
                }
                _ = self.ops.pop();
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduce();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    fn reduce(self: *Evaluator) Error!void {
        const op = self.ops.pop().?;
        const values = &self.values;
        if (op == .neg) {
            const top = &values.items[values.items.len - 1];
            top.* = try std.math.negate(top.*);
        } else {
            const b = values.pop().?;
            const top = &values.items[values.items.len - 1];
            top.* = try applyBinary(op, top.*, b);
        }
    }
};

fn expectValue(expected: i64, line: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectEqual(expected, try ev.evaluate(line));
}

fn expectFailure(expected: Error, line: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectError(expected, ev.evaluate(line));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(70, "2*(3+4)*5");
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
}

test "overflow" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "syntax errors" {
    try expectFailure(error.Syntax, "1 +");
    try expectFailure(error.Syntax, "abc");
    try expectFailure(error.Syntax, "()");
    try expectFailure(error.Syntax, "1 2");
    try expectFailure(error.Syntax, "+1");
    try expectFailure(error.Syntax, "(1 + 2");
    try expectFailure(error.Syntax, "1 + 2)");
    try expectFailure(error.Syntax, "1\r");
}

test "blank lines" {
    try std.testing.expect(isBlankLine(""));
    try std.testing.expect(isBlankLine(" \t "));
    try std.testing.expect(!isBlankLine(" 1 "));
}
