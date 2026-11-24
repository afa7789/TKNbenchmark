//! Evaluates integer expressions of the form described in SPEC.md.
//!
//! Parsing uses an operator-precedence (shunting-yard) algorithm with explicit
//! stacks rather than recursion, so arbitrarily deep nesting such as
//! `((((...))))` or `------1` cannot overflow the call stack. The stacks are
//! retained between calls to avoid reallocating for every line.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

allocator: Allocator,
values: std.ArrayList(i64) = .empty,
ops: std.ArrayList(Op) = .empty,

pub const Error = error{
    /// The input does not match the grammar.
    Syntax,
    DivisionByZero,
    /// A literal or intermediate result does not fit in an `i64`.
    Overflow,
} || Allocator.Error;

const Op = enum {
    left_paren,
    negate,
    add,
    sub,
    mul,
    div,
    rem,

    /// Binding strength; higher binds tighter. `left_paren` acts as a barrier.
    fn precedence(op: Op) u8 {
        return switch (op) {
            .left_paren => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .negate => 3,
        };
    }

    fn binary(c: u8) ?Op {
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

pub fn init(allocator: Allocator) Evaluator {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Evaluator) void {
    self.values.deinit(self.allocator);
    self.ops.deinit(self.allocator);
    self.* = undefined;
}

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Evaluates one line. Returns `null` if the line is empty or contains only
/// spaces and tabs.
pub fn evaluate(self: *Evaluator, line: []const u8) Error!?i64 {
    self.values.clearRetainingCapacity();
    self.ops.clearRetainingCapacity();

    var expect_operand = true;
    var seen_token = false;
    var i: usize = 0;
    while (true) {
        while (i < line.len and isBlank(line[i])) i += 1;
        if (i == line.len) break;
        seen_token = true;

        const c = line[i];
        if (expect_operand) {
            switch (c) {
                '-' => {
                    try self.ops.append(self.allocator, .negate);
                    i += 1;
                },
                '(' => {
                    try self.ops.append(self.allocator, .left_paren);
                    i += 1;
                },
                '0'...'9' => {
                    var value: i64 = 0;
                    while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {
                        value = try std.math.mul(i64, value, 10);
                        value = try std.math.add(i64, value, line[i] - '0');
                    }
                    try self.values.append(self.allocator, value);
                    expect_operand = false;
                },
                else => return error.Syntax,
            }
        } else if (Op.binary(c)) |op| {
            try self.reduce(op.precedence());
            try self.ops.append(self.allocator, op);
            expect_operand = true;
            i += 1;
        } else if (c == ')') {
            try self.reduce(0);
            if (self.ops.pop() != .left_paren) return error.Syntax;
            i += 1;
        } else {
            return error.Syntax;
        }
    }

    if (!seen_token) return null;
    if (expect_operand) return error.Syntax;
    try self.reduce(0);
    if (self.ops.items.len != 0) return error.Syntax; // unclosed '('
    std.debug.assert(self.values.items.len == 1);
    return self.values.items[0];
}

/// Applies stacked operators whose precedence is at least `min_precedence`,
/// stopping at the nearest unmatched `(`.
fn reduce(self: *Evaluator, min_precedence: u8) Error!void {
    while (self.ops.getLastOrNull()) |op| {
        if (op == .left_paren or op.precedence() < min_precedence) break;
        _ = self.ops.pop();
        // The parser state machine guarantees operands are present.
        const rhs = self.values.pop().?;
        if (op == .negate) {
            self.values.appendAssumeCapacity(try std.math.negate(rhs));
            continue;
        }
        const lhs = self.values.pop().?;
        self.values.appendAssumeCapacity(try apply(op, lhs, rhs));
    }
}

fn apply(op: Op, lhs: i64, rhs: i64) Error!i64 {
    return switch (op) {
        .add => std.math.add(i64, lhs, rhs),
        .sub => std.math.sub(i64, lhs, rhs),
        .mul => std.math.mul(i64, lhs, rhs),
        .div => {
            if (rhs == 0) return error.DivisionByZero;
            if (lhs == std.math.minInt(i64) and rhs == -1) return error.Overflow;
            return @divTrunc(lhs, rhs);
        },
        .rem => {
            if (rhs == 0) return error.DivisionByZero;
            // The quotient may overflow, but the remainder is always 0.
            if (rhs == -1) return 0;
            return @rem(lhs, rhs);
        },
        .left_paren, .negate => unreachable,
    };
}

fn expectValue(expected: ?i64, line: []const u8) !void {
    var e = init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectEqual(expected, try e.evaluate(line));
}

fn expectFailure(expected: Error, line: []const u8) !void {
    var e = init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectError(expected, e.evaluate(line));
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
    try expectValue(42, " \t42\t ");
    try expectValue(7, "007");
}

test "blank lines" {
    try expectValue(null, "");
    try expectValue(null, " \t ");
}

test "64-bit limits" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "errors" {
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % 0");
    inline for (.{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 1", "1 * * 2", "1\r", "- ", "(" }) |line| {
        try expectFailure(error.Syntax, line);
    }
}

test "deep nesting does not recurse" {
    const depth = 100_000;
    const line = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(line);
    @memset(line[0..depth], '(');
    line[depth] = '1';
    @memset(line[depth + 1 ..], ')');
    try expectValue(1, line);
    @memset(line[0..depth], '-');
    try expectValue(1, line[0 .. depth + 1]);
}
