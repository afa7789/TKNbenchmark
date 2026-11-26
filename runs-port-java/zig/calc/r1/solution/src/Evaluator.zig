//! Evaluator for signed 64-bit integer expressions:
//!
//!     expr    := term    (('+' | '-') term)*
//!     term    := unary   (('*' | '/' | '%') unary)*
//!     unary   := '-' unary | primary
//!     primary := NUMBER | '(' expr ')'
//!
//! Parsing uses operator-precedence (shunting-yard) with explicit stacks, so
//! arbitrarily deep nesting cannot overflow the call stack. The stacks are
//! retained between calls to `evaluate` to avoid reallocating for every line.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

pub const Error = error{
    SyntaxError,
    DivisionByZero,
    Overflow,
    OutOfMemory,
};

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    /// Opening parenthesis; acts as a barrier while reducing.
    group,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .group => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
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

/// True if the line holds only spaces and tabs.
pub fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (!isSpace(c)) return false;
    }
    return true;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Returns the value of `src`, or an error if it is malformed or any
/// intermediate result is not representable as an `i64`.
pub fn evaluate(self: *Evaluator, src: []const u8) Error!i64 {
    self.values.clearRetainingCapacity();
    self.ops.clearRetainingCapacity();

    var pos: usize = 0;
    // Whether the next token must be an operand (as opposed to an operator).
    var want_operand = true;

    while (true) {
        while (pos < src.len and isSpace(src[pos])) pos += 1;
        if (pos == src.len) break;
        const c = src[pos];

        if (want_operand) {
            switch (c) {
                '-' => {
                    try self.ops.append(self.gpa, .neg);
                    pos += 1;
                },
                '(' => {
                    try self.ops.append(self.gpa, .group);
                    pos += 1;
                },
                '0'...'9' => {
                    const start = pos;
                    while (pos < src.len and std.ascii.isDigit(src[pos])) pos += 1;
                    try self.values.append(self.gpa, try parseNumber(src[start..pos]));
                    want_operand = false;
                },
                else => return error.SyntaxError,
            }
        } else if (c == ')') {
            try self.reduceWhile(Op.group.precedence() + 1);
            if (self.ops.pop() != .group) return error.SyntaxError;
            pos += 1;
        } else if (Op.fromByte(c)) |op| {
            // Left-associative: first apply pending operators that bind at least as tightly.
            try self.reduceWhile(op.precedence());
            try self.ops.append(self.gpa, op);
            pos += 1;
            want_operand = true;
        } else {
            return error.SyntaxError;
        }
    }

    if (want_operand) return error.SyntaxError;
    try self.reduceWhile(Op.group.precedence() + 1);
    if (self.ops.items.len != 0) return error.SyntaxError; // unclosed '('
    std.debug.assert(self.values.items.len == 1);
    return self.values.items[0];
}

/// Applies operators from the top of the stack while their precedence is at
/// least `min_precedence`. Never pops a `group`, whose precedence is lowest.
fn reduceWhile(self: *Evaluator, min_precedence: u8) Error!void {
    while (self.ops.getLastOrNull()) |op| {
        if (op.precedence() < min_precedence) return;
        _ = self.ops.pop();
        if (op == .neg) {
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try std.math.negate(top.*);
        } else {
            const rhs = self.values.pop().?;
            const lhs = &self.values.items[self.values.items.len - 1];
            lhs.* = try applyBinary(op, lhs.*, rhs);
        }
    }
}

fn applyBinary(op: Op, lhs: i64, rhs: i64) Error!i64 {
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
            // minInt(i64) % -1 is mathematically 0; avoid the overflowing division.
            if (rhs == -1) return 0;
            return @rem(lhs, rhs);
        },
        .neg, .group => unreachable,
    };
}

/// Parses a non-empty run of ASCII digits.
fn parseNumber(digits: []const u8) error{Overflow}!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, d - '0');
    }
    return value;
}

fn expectValue(expected: i64, src: []const u8) !void {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    try std.testing.expectEqual(expected, try evaluator.evaluate(src));
}

fn expectFailure(expected: Error, src: []const u8) !void {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    try std.testing.expectError(expected, evaluator.evaluate(src));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(2, "100 / 10 / 5");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(42, "\t 42 ");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-6, "-2 * 3");
    try expectValue(-7, "- 2 * 3 - 1");
}

test "division and remainder" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % (2 - 2)");
}

test "overflow" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "syntax errors" {
    for ([_][]const u8{ "", "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 (2)", "1\r", "* 2" }) |src| {
        try expectFailure(error.SyntaxError, src);
    }
}

test "deep nesting" {
    const depth = 100_000;
    const src = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(src);
    @memset(src[0..depth], '(');
    src[depth] = '7';
    @memset(src[depth + 1 ..], ')');
    try expectValue(7, src);
}

test "isBlank" {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank(" 1 "));
}
