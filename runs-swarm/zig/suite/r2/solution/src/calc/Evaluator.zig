//! Evaluates one `calc` expression (see SPEC.md) over signed 64-bit integers.
//!
//! Parsing is an iterative operator-precedence (shunting-yard) algorithm with
//! explicit stacks, so arbitrarily deep nesting of parentheses or unary minus
//! cannot overflow the call stack. The stacks are kept between calls so that
//! evaluating many lines reuses their capacity.

const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

const Evaluator = @This();

gpa: Allocator,
values: std.ArrayList(i64) = .empty,
ops: std.ArrayList(Op) = .empty,

pub const Error = error{
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the range of `i64`.
    Overflow,
} || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    /// Open parenthesis: a barrier that no reduction crosses.
    lparen,

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

pub fn init(gpa: Allocator) Evaluator {
    return .{ .gpa = gpa };
}

pub fn deinit(e: *Evaluator) void {
    e.values.deinit(e.gpa);
    e.ops.deinit(e.gpa);
    e.* = undefined;
}

/// Returns the value of `source`, which must hold a complete expression.
pub fn eval(e: *Evaluator, source: []const u8) Error!i64 {
    e.values.clearRetainingCapacity();
    e.ops.clearRetainingCapacity();

    // Whether the next token must start an operand (number, '(' or unary
    // '-') rather than continue one (binary operator or ')').
    var expect_operand = true;
    var i: usize = 0;
    while (i < source.len) {
        const c = source[i];
        if (c == ' ' or c == '\t') {
            i += 1;
            continue;
        }
        if (expect_operand) {
            switch (c) {
                '-' => try e.ops.append(e.gpa, .neg),
                '(' => try e.ops.append(e.gpa, .lparen),
                '0'...'9' => {
                    var value: i64 = 0;
                    while (i < source.len and std.ascii.isDigit(source[i])) : (i += 1) {
                        value = try math.add(i64, try math.mul(i64, value, 10), source[i] - '0');
                    }
                    try e.values.append(e.gpa, value);
                    expect_operand = false;
                    continue;
                },
                else => return error.Syntax,
            }
        } else if (c == ')') {
            try e.reduceWhile(0);
            if (e.ops.pop() != .lparen) return error.Syntax;
        } else {
            const op = Op.fromBinary(c) orelse return error.Syntax;
            // Left associativity: reduce operators of equal precedence too.
            try e.reduceWhile(op.precedence() - 1);
            try e.ops.append(e.gpa, op);
            expect_operand = true;
        }
        i += 1;
    }
    if (expect_operand) return error.Syntax;

    try e.reduceWhile(0);
    if (e.ops.items.len != 0) return error.Syntax; // unclosed '('
    std.debug.assert(e.values.items.len == 1);
    return e.values.items[0];
}

/// Applies stacked operators while their precedence exceeds `min`.
fn reduceWhile(e: *Evaluator, min: u8) Error!void {
    while (e.ops.items.len > 0) {
        const op = e.ops.getLast();
        if (op.precedence() <= min) break;
        _ = e.ops.pop();
        if (op == .neg) {
            const top = &e.values.items[e.values.items.len - 1];
            top.* = try math.negate(top.*);
        } else {
            const rhs = e.values.pop().?;
            const lhs = &e.values.items[e.values.items.len - 1];
            lhs.* = try apply(op, lhs.*, rhs);
        }
    }
}

fn apply(op: Op, lhs: i64, rhs: i64) Error!i64 {
    return switch (op) {
        .add => math.add(i64, lhs, rhs),
        .sub => math.sub(i64, lhs, rhs),
        .mul => math.mul(i64, lhs, rhs),
        .div => {
            if (rhs == 0) return error.DivisionByZero;
            if (lhs == math.minInt(i64) and rhs == -1) return error.Overflow;
            return @divTrunc(lhs, rhs);
        },
        .rem => {
            if (rhs == 0) return error.DivisionByZero;
            // The quotient may overflow, but the remainder is always 0.
            if (rhs == -1) return 0;
            return @rem(lhs, rhs);
        },
        .neg, .lparen => unreachable,
    };
}

fn expectValue(expected: i64, source: []const u8) !void {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectEqual(expected, try e.eval(source));
}

fn expectError(expected: Error, source: []const u8) !void {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectError(expected, e.eval(source));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(2, "100 / 10 / 5");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(42, "\t ( ( 42 ) ) ");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-6, "-2 * 3");
    try expectValue(-9223372036854775807 - 1, "-9223372036854775807 - 1");
}

test "division and remainder" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectError(error.DivisionByZero, "1 / 0");
    try expectError(error.DivisionByZero, "5 % (2 - 2)");
}

test "overflow" {
    try expectValue(9223372036854775807, "0009223372036854775807");
    try expectError(error.Overflow, "9223372036854775808");
    try expectError(error.Overflow, "-9223372036854775808");
    try expectError(error.Overflow, "9223372036854775807 + 1");
    try expectError(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectError(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectError(error.Overflow, "4294967296 * 4294967296");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 (2)", "2 -", "1 +* 2", "1\r" }) |source| {
        try expectError(error.Syntax, source);
    }
}

test "deep nesting" {
    const depth = 100_000;
    const source = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(source);
    @memset(source[0..depth], '(');
    source[depth] = '7';
    @memset(source[depth + 1 ..], ')');
    try expectValue(7, source);
    @memset(source[0..depth], '-');
    try expectValue(7, source[0 .. depth + 1]);
}
