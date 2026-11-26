//! Signed 64-bit integer expression evaluator.
//!
//! Uses an iterative operator-precedence (shunting-yard) parser so that
//! arbitrarily deep nesting cannot exhaust the call stack. The operand and
//! operator stacks are kept between calls so evaluating many lines reuses
//! the same allocations.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

pub const Error = error{
    /// Any character outside the grammar, unbalanced parentheses, missing operand.
    SyntaxError,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the i64 range.
    Overflow,
} || Allocator.Error;

const Op = enum {
    lparen,
    negate,
    add,
    sub,
    mul,
    div,
    rem,

    fn precedence(op: Op) u2 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .negate => 3,
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

/// Evaluates one expression. Returns `null` when the line holds only
/// spaces and tabs.
pub fn evaluate(self: *Evaluator, line: []const u8) Error!?i64 {
    self.values.clearRetainingCapacity();
    self.ops.clearRetainingCapacity();

    var expect_operand = true;
    var saw_token = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (c == ' ' or c == '\t') continue;
        saw_token = true;

        if (expect_operand) {
            switch (c) {
                '0'...'9' => {
                    const start = i;
                    while (i + 1 < line.len and std.ascii.isDigit(line[i + 1])) i += 1;
                    try self.values.append(self.gpa, try parseLiteral(line[start .. i + 1]));
                    expect_operand = false;
                },
                '-' => try self.ops.append(self.gpa, .negate),
                '(' => try self.ops.append(self.gpa, .lparen),
                else => return error.SyntaxError,
            }
            continue;
        }

        if (Op.fromBinary(c)) |op| {
            // All binary operators are left-associative.
            while (self.ops.getLastOrNull()) |top| {
                if (top.precedence() < op.precedence()) break;
                try self.reduceTop();
            }
            try self.ops.append(self.gpa, op);
            expect_operand = true;
        } else if (c == ')') {
            while (true) {
                const top = self.ops.getLastOrNull() orelse return error.SyntaxError;
                if (top == .lparen) break;
                try self.reduceTop();
            }
            _ = self.ops.pop();
        } else {
            return error.SyntaxError;
        }
    }

    if (!saw_token) return null;
    if (expect_operand) return error.SyntaxError;
    while (self.ops.getLastOrNull()) |top| {
        if (top == .lparen) return error.SyntaxError;
        try self.reduceTop();
    }
    std.debug.assert(self.values.items.len == 1);
    return self.values.items[0];
}

fn parseLiteral(digits: []const u8) Error!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, d - '0');
    }
    return value;
}

fn reduceTop(self: *Evaluator) Error!void {
    const op = self.ops.pop().?;
    if (op == .negate) {
        const a = &self.values.items[self.values.items.len - 1];
        a.* = try std.math.negate(a.*);
        return;
    }
    const b = self.values.pop().?;
    const a = &self.values.items[self.values.items.len - 1];
    a.* = try applyBinary(op, a.*, b);
}

fn applyBinary(op: Op, a: i64, b: i64) Error!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => std.math.divTrunc(i64, a, b),
        // The remainder never overflows; `minInt % -1` is 0.
        .rem => if (b == 0) error.DivisionByZero else if (b == -1) 0 else @rem(a, b),
        .lparen, .negate => unreachable,
    };
}

fn expectValue(expected: ?i64, line: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectEqual(expected, try ev.evaluate(line));
}

fn expectError(expected: Error, line: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectError(expected, ev.evaluate(line));
}

test "arithmetic and precedence" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(5, "--5");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(3, "1 - -2");
    try expectValue(null, " \t ");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
}

test "errors" {
    try expectError(error.SyntaxError, "(1 + 2");
    try expectError(error.SyntaxError, "1 2");
    try expectError(error.SyntaxError, "+1");
    try expectError(error.SyntaxError, "()");
    try expectError(error.SyntaxError, "1 +");
    try expectError(error.SyntaxError, "1)");
    try expectError(error.DivisionByZero, "1 / 0");
    try expectError(error.DivisionByZero, "1 % 0");
    try expectError(error.Overflow, "9223372036854775807 + 1");
    try expectError(error.Overflow, "9223372036854775808");
    try expectError(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectError(error.Overflow, "-(-9223372036854775807 - 1)");
}
