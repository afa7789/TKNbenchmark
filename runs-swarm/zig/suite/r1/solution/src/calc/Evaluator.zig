//! Evaluates one line of the calc grammar (see the "calc" section of SPEC.md)
//! over signed 64-bit integers.
//!
//! The parser is an operator-precedence (shunting-yard) machine with explicit
//! stacks rather than recursive descent, so arbitrarily deep nesting such as
//! `((((…))))` or `------1` is bounded by heap memory, not by the call stack.
//! The stacks are kept between calls so that evaluating many lines reuses
//! their capacity.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

gpa: Allocator,
values: std.ArrayList(i64) = .empty,
operators: std.ArrayList(Operator) = .empty,

pub const Error = error{
    /// The input does not match the grammar.
    Syntax,
    /// A `/` or `%` whose right operand is zero.
    DivisionByZero,
    /// A literal or intermediate result outside the range of `i64`.
    Overflow,
} || Allocator.Error;

const Operator = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    /// Marks an open parenthesis; never applied.
    group,

    /// Binding strength; higher binds tighter. Binary operators are
    /// left-associative and `neg` is a prefix operator, so an operator on the
    /// stack is applied before pushing one of lower or equal precedence.
    fn precedence(op: Operator) u8 {
        return switch (op) {
            .group => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
        };
    }
};

pub fn init(gpa: Allocator) Evaluator {
    return .{ .gpa = gpa };
}

pub fn deinit(e: *Evaluator) void {
    e.values.deinit(e.gpa);
    e.operators.deinit(e.gpa);
    e.* = undefined;
}

/// Returns the value of the expression in `line`, which must not contain the
/// line terminator. A line holding only blanks is a syntax error; callers
/// decide separately whether such lines produce output.
pub fn evaluate(e: *Evaluator, line: []const u8) Error!i64 {
    e.values.clearRetainingCapacity();
    e.operators.clearRetainingCapacity();

    // True where the grammar requires an operand: at the start, after an
    // operator and after `(`. False after a number or `)`.
    var expect_operand = true;
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        switch (c) {
            ' ', '\t' => i += 1,
            '0'...'9' => {
                if (!expect_operand) return error.Syntax;
                var value: i64 = 0;
                while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {
                    value = try mul(value, 10);
                    value = try add(value, line[i] - '0');
                }
                try e.values.append(e.gpa, value);
                expect_operand = false;
            },
            '(' => {
                if (!expect_operand) return error.Syntax;
                try e.operators.append(e.gpa, .group);
                i += 1;
            },
            ')' => {
                if (expect_operand) return error.Syntax;
                try e.reduce(Operator.group.precedence() + 1);
                if (e.operators.pop() != .group) return error.Syntax;
                i += 1;
            },
            '-' => {
                if (expect_operand) {
                    try e.operators.append(e.gpa, .neg);
                } else {
                    try e.pushBinary(.sub);
                    expect_operand = true;
                }
                i += 1;
            },
            '+', '*', '/', '%' => {
                if (expect_operand) return error.Syntax;
                try e.pushBinary(switch (c) {
                    '+' => .add,
                    '*' => .mul,
                    '/' => .div,
                    '%' => .rem,
                    else => unreachable,
                });
                expect_operand = true;
                i += 1;
            },
            else => return error.Syntax,
        }
    }
    if (expect_operand) return error.Syntax;

    try e.reduce(Operator.group.precedence() + 1);
    if (e.operators.items.len != 0) return error.Syntax; // unclosed `(`
    std.debug.assert(e.values.items.len == 1);
    return e.values.items[0];
}

fn pushBinary(e: *Evaluator, op: Operator) Error!void {
    try e.reduce(op.precedence());
    try e.operators.append(e.gpa, op);
}

/// Applies stacked operators while their precedence is at least `min`.
/// Stops at an open parenthesis whenever `min` is above its precedence.
fn reduce(e: *Evaluator, min: u8) Error!void {
    while (e.operators.getLastOrNull()) |op| {
        if (op.precedence() < min) break;
        _ = e.operators.pop();
        try e.apply(op);
    }
}

/// Pops the operands of `op` from the value stack and pushes its result.
/// The operator/operand alternation enforced by `evaluate` guarantees the
/// operands are present.
fn apply(e: *Evaluator, op: Operator) Error!void {
    const values = &e.values.items;
    if (op == .neg) {
        const top = &values.*[values.len - 1];
        top.* = try sub(0, top.*);
        return;
    }
    const rhs = e.values.pop().?;
    const lhs = &values.*[values.len - 1];
    lhs.* = switch (op) {
        .add => try add(lhs.*, rhs),
        .sub => try sub(lhs.*, rhs),
        .mul => try mul(lhs.*, rhs),
        .div => try div(lhs.*, rhs),
        .rem => try rem(lhs.*, rhs),
        .neg, .group => unreachable,
    };
}

fn add(a: i64, b: i64) error{Overflow}!i64 {
    const r = @addWithOverflow(a, b);
    return if (r[1] != 0) error.Overflow else r[0];
}

fn sub(a: i64, b: i64) error{Overflow}!i64 {
    const r = @subWithOverflow(a, b);
    return if (r[1] != 0) error.Overflow else r[0];
}

fn mul(a: i64, b: i64) error{Overflow}!i64 {
    const r = @mulWithOverflow(a, b);
    return if (r[1] != 0) error.Overflow else r[0];
}

/// Division truncating toward zero.
fn div(a: i64, b: i64) error{ DivisionByZero, Overflow }!i64 {
    if (b == 0) return error.DivisionByZero;
    if (b == -1) return sub(0, a);
    return @divTrunc(a, b);
}

/// Remainder of truncating division: its sign follows the dividend.
fn rem(a: i64, b: i64) error{DivisionByZero}!i64 {
    if (b == 0) return error.DivisionByZero;
    // The quotient minInt / -1 overflows, but the remainder is exactly 0.
    if (b == -1) return 0;
    return @rem(a, b);
}

fn expectValue(expected: i64, line: []const u8) !void {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectEqual(expected, try e.evaluate(line));
}

fn expectError(expected: Error, line: []const u8) !void {
    var e: Evaluator = .init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectError(expected, e.evaluate(line));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(2, "100 / 10 / 5");
    try expectValue(1, "17 % 10 % 3");
    try expectValue(42, "  \t42\t ");
    try expectValue(7, "007");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-6, "-2 * 3");
    try expectValue(-1, "- 7 % 3");
    try expectValue(-9223372036854775807, "-9223372036854775807");
}

test "division and remainder" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectValue(9223372036854775807, "9223372036854775807 / 1");
    try expectError(error.DivisionByZero, "1 / 0");
    try expectError(error.DivisionByZero, "5 % (2 - 2)");
}

test "overflow" {
    try expectError(error.Overflow, "9223372036854775808");
    try expectError(error.Overflow, "-9223372036854775808");
    try expectError(error.Overflow, "9223372036854775807 + 1");
    try expectError(error.Overflow, "-9223372036854775807 - 2");
    try expectError(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectError(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectError(error.Overflow, "4611686018427387904 * 2");
    try expectValue(-9223372036854775807 - 1, "-4611686018427387904 * 2");
}

test "syntax errors" {
    for ([_][]const u8{
        "", "   ", "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)",
        ")(", "1 (2)", "(1) 2", "1 * * 2", "1 -", "-", "1\r", "2 ** 3",
    }) |line| try expectError(error.Syntax, line);
}

test "deep nesting does not recurse" {
    const depth = 100_000;
    const line = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(line);
    @memset(line[0..depth], '(');
    line[depth] = '1';
    @memset(line[depth + 1 ..], ')');
    try expectValue(1, line);

    @memset(line[0 .. 2 * depth], '-');
    line[2 * depth] = '3';
    try expectValue(3, line);
}
