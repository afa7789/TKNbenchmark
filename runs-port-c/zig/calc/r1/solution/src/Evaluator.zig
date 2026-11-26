//! Iterative operator-precedence (shunting-yard) evaluator for 64-bit signed
//! integer expressions.
//!
//! Operand and operator stacks live on the heap and are reused across calls,
//! so arbitrarily deep nesting cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

pub const Error = error{
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result is outside the range of `i64`.
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

    /// Binding strength; `lparen` is 0 so it is never reduced implicitly.
    fn precedence(op: Op) u2 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
        };
    }
};

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

/// Evaluates a single expression. Leading, trailing and inter-token spaces
/// and tabs are ignored.
pub fn evaluate(self: *Evaluator, text: []const u8) Error!i64 {
    self.values.clearRetainingCapacity();
    self.ops.clearRetainingCapacity();

    var expect_operand = true;
    var i: usize = 0;
    while (true) {
        while (i < text.len and isSpace(text[i])) i += 1;
        if (i == text.len) break;

        const c = text[i];
        if (expect_operand) {
            switch (c) {
                '0'...'9' => {
                    const start = i;
                    while (i < text.len and std.ascii.isDigit(text[i])) i += 1;
                    try self.values.append(self.gpa, try parseLiteral(text[start..i]));
                    expect_operand = false;
                    continue;
                },
                '-' => try self.ops.append(self.gpa, .neg),
                '(' => try self.ops.append(self.gpa, .lparen),
                else => return error.Syntax,
            }
        } else if (Op.fromBinary(c)) |op| {
            try self.reduce(op.precedence());
            try self.ops.append(self.gpa, op);
            expect_operand = true;
        } else if (c == ')') {
            try self.reduce(1);
            // The top operator, if any, is now the matching '('.
            if (self.ops.pop() == null) return error.Syntax;
        } else {
            return error.Syntax;
        }
        i += 1;
    }

    if (expect_operand) return error.Syntax;
    try self.reduce(1);
    if (self.ops.items.len != 0 or self.values.items.len != 1) return error.Syntax;
    return self.values.items[0];
}

/// Pops and applies operators whose precedence is at least `min_prec`
/// (which must be at least 1), stopping at a '('.
fn reduce(self: *Evaluator, min_prec: u2) Error!void {
    std.debug.assert(min_prec >= 1);
    while (self.ops.getLastOrNull()) |top| {
        if (top.precedence() < min_prec) break;
        _ = self.ops.pop();
        try self.apply(top);
    }
}

fn apply(self: *Evaluator, op: Op) Error!void {
    const values = self.values.items;
    if (op == .neg) {
        if (values.len < 1) return error.Syntax;
        const a = &values[values.len - 1];
        a.* = try std.math.negate(a.*);
        return;
    }
    if (values.len < 2) return error.Syntax;
    const b = self.values.pop().?;
    const a = &values[values.len - 2];
    a.* = switch (op) {
        .add => try std.math.add(i64, a.*, b),
        .sub => try std.math.sub(i64, a.*, b),
        .mul => try std.math.mul(i64, a.*, b),
        .div => try std.math.divTrunc(i64, a.*, b),
        .rem => try truncatedRem(a.*, b),
        .neg, .lparen => unreachable,
    };
}

/// Remainder of truncating division; its sign follows the dividend.
/// `minInt(i64) % -1` is 0 rather than an overflow.
fn truncatedRem(a: i64, b: i64) error{DivisionByZero}!i64 {
    if (b == 0) return error.DivisionByZero;
    if (b == -1) return 0;
    return @rem(a, b);
}

fn parseLiteral(digits: []const u8) error{Overflow}!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, d - '0');
    }
    return value;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn testEval(text: []const u8) Error!i64 {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    return ev.evaluate(text);
}

test "arithmetic and precedence" {
    try std.testing.expectEqual(7, try testEval("1 + 2 * 3"));
    try std.testing.expectEqual(9, try testEval("(1 + 2) * 3"));
    try std.testing.expectEqual(5, try testEval("1 + 2 * 3 - 4 / 2 % 3"));
    try std.testing.expectEqual(3, try testEval("10 - 4 - 3"));
    try std.testing.expectEqual(5, try testEval("--5"));
    try std.testing.expectEqual(-5, try testEval("-(2 + 3)"));
    try std.testing.expectEqual(3, try testEval("1 - -2"));
    try std.testing.expectEqual(42, try testEval("\t42 "));
}

test "division semantics" {
    try std.testing.expectEqual(-3, try testEval("-7 / 2"));
    try std.testing.expectEqual(-1, try testEval("-7 % 3"));
    try std.testing.expectEqual(1, try testEval("7 % -3"));
    try std.testing.expectEqual(0, try testEval("(-9223372036854775807 - 1) % -1"));
    try std.testing.expectError(error.DivisionByZero, testEval("1 / 0"));
    try std.testing.expectError(error.DivisionByZero, testEval("1 % 0"));
}

test "overflow" {
    try std.testing.expectEqual(std.math.maxInt(i64), try testEval("9223372036854775807"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775808"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775807 + 1"));
    try std.testing.expectError(error.Overflow, testEval("-9223372036854775807 - 2"));
    try std.testing.expectError(error.Overflow, testEval("3037000500 * 3037000500"));
    try std.testing.expectError(error.Overflow, testEval("(-9223372036854775807 - 1) / -1"));
    try std.testing.expectError(error.Overflow, testEval("-(-9223372036854775807 - 1)"));
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 -", "2 * * 3", "1\r" }) |text| {
        try std.testing.expectError(error.Syntax, testEval(text));
    }
}

test "deep nesting" {
    const depth = 100_000;
    var buf: [2 * depth + 1]u8 = undefined;
    @memset(buf[0..depth], '(');
    buf[depth] = '1';
    @memset(buf[depth + 1 ..], ')');
    try std.testing.expectEqual(1, try testEval(&buf));
}
