//! Evaluator for signed 64-bit integer arithmetic expressions.
//!
//! Grammar:
//!   expr    := term    (('+' | '-') term)*
//!   term    := unary   (('*' | '/' | '%') unary)*
//!   unary   := '-' unary | primary
//!   primary := NUMBER | '(' expr ')'
//!
//! Parsing is iterative (operator precedence with explicit stacks) so that
//! deeply nested input cannot overflow the call stack.

const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

pub const Error = error{
    SyntaxError,
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
    open,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
            .open => 0,
        };
    }

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
};

fn applyBinary(op: Op, a: i64, b: i64) Error!i64 {
    return switch (op) {
        .add => math.add(i64, a, b),
        .sub => math.sub(i64, a, b),
        .mul => math.mul(i64, a, b),
        .div => blk: {
            if (b == 0) return error.DivisionByZero;
            if (a == math.minInt(i64) and b == -1) return error.Overflow;
            break :blk @divTrunc(a, b);
        },
        .rem => blk: {
            if (b == 0) return error.DivisionByZero;
            // The exact remainder is always representable; avoid the
            // minInt / -1 trap of the underlying division.
            if (b == -1) break :blk 0;
            break :blk @rem(a, b);
        },
        .neg, .open => unreachable,
    };
}

/// Reusable evaluation state. Stacks retain their capacity between calls.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Evaluates one expression.
    pub fn evaluate(self: *Evaluator, gpa: Allocator, source: []const u8) Error!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        // true: the next token must start an operand; false: an operator or ')'.
        var expect_operand = true;
        var i: usize = 0;
        while (i < source.len) {
            const c = source[i];
            switch (c) {
                ' ', '\t' => i += 1,
                '0'...'9' => {
                    if (!expect_operand) return error.SyntaxError;
                    var value: i64 = 0;
                    while (i < source.len and std.ascii.isDigit(source[i])) : (i += 1) {
                        value = try math.add(i64, try math.mul(i64, value, 10), source[i] - '0');
                    }
                    try self.values.append(gpa, value);
                    expect_operand = false;
                },
                else => {
                    i += 1;
                    if (expect_operand) {
                        switch (c) {
                            '-' => try self.ops.append(gpa, .neg),
                            '(' => try self.ops.append(gpa, .open),
                            else => return error.SyntaxError,
                        }
                    } else if (Op.fromByte(c)) |op| {
                        try self.pushBinary(gpa, op);
                        expect_operand = true;
                    } else if (c == ')') {
                        try self.close();
                    } else {
                        return error.SyntaxError;
                    }
                },
            }
        }

        if (expect_operand) return error.SyntaxError;
        return self.finish();
    }

    /// Reduces pending operators that bind at least as tightly, then pushes `op`.
    fn pushBinary(self: *Evaluator, gpa: Allocator, op: Op) Error!void {
        const prec = op.precedence();
        while (self.ops.getLastOrNull()) |top| {
            if (top == .open or top.precedence() < prec) break;
            try self.reduceTop();
        }
        try self.ops.append(gpa, op);
    }

    /// Reduces up to and including the matching '('.
    fn close(self: *Evaluator) Error!void {
        while (self.ops.getLastOrNull()) |top| {
            if (top == .open) {
                _ = self.ops.pop();
                return;
            }
            try self.reduceTop();
        }
        return error.SyntaxError;
    }

    fn finish(self: *Evaluator) Error!i64 {
        while (self.ops.getLastOrNull()) |top| {
            if (top == .open) return error.SyntaxError;
            try self.reduceTop();
        }
        if (self.values.items.len != 1) return error.SyntaxError;
        return self.values.items[0];
    }

    fn reduceTop(self: *Evaluator) Error!void {
        const op = self.ops.pop().?;
        if (op == .neg) {
            const a = self.values.pop() orelse return error.SyntaxError;
            self.values.appendAssumeCapacity(try math.negate(a));
            return;
        }
        const b = self.values.pop() orelse return error.SyntaxError;
        const a = self.values.pop() orelse return error.SyntaxError;
        self.values.appendAssumeCapacity(try applyBinary(op, a, b));
    }
};

/// Returns true when the line contains only spaces and tabs.
pub fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (c != ' ' and c != '\t') return false;
    }
    return true;
}

fn expectValue(expected: i64, source: []const u8) !void {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, try ev.evaluate(std.testing.allocator, source));
}

fn expectFailure(expected: Error, source: []const u8) !void {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    try std.testing.expectError(expected, ev.evaluate(std.testing.allocator, source));
}

test "arithmetic and precedence" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(42, "\t 42  ");
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
    try expectValue(math.minInt(i64), "-9223372036854775807 - 1");
}

test "overflow" {
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "2(3)", "1\r", "-" }) |src| {
        try expectFailure(error.SyntaxError, src);
    }
}

test "blank lines" {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank(" 1 "));
}
