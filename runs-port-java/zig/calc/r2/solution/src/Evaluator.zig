//! Evaluator for 64-bit signed integer expressions.
//!
//! ```
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! Spaces and tabs may separate tokens. Parsing uses operator-precedence
//! (shunting-yard) with explicit stacks rather than recursion, so arbitrarily
//! deep nesting is bounded only by available memory. The stacks are retained
//! between calls, making repeated evaluation allocation-free in steady state.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

values: std.ArrayList(i64) = .empty,
ops: std.ArrayList(Op) = .empty,

pub const Error = error{
    /// Character outside the grammar, unbalanced parentheses, missing operand, ...
    SyntaxError,
    DivisionByZero,
    /// A literal or an intermediate result lies outside the `i64` range.
    Overflow,
} || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    negate,
    /// Marks an unclosed '(' on the operator stack.
    open,

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

    /// Binding strength of binary operators; zero for anything that must not
    /// be reduced by an incoming binary operator.
    fn precedence(op: Op) u2 {
        return switch (op) {
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .negate, .open => 0,
        };
    }
};

pub fn deinit(self: *Evaluator, gpa: Allocator) void {
    self.values.deinit(gpa);
    self.ops.deinit(gpa);
    self.* = undefined;
}

/// Evaluates `line` as one complete expression.
pub fn evaluate(self: *Evaluator, gpa: Allocator, line: []const u8) Error!i64 {
    self.values.clearRetainingCapacity();
    self.ops.clearRetainingCapacity();

    var pos: usize = 0;
    while (true) {
        // Operand position: any number of '-' and '(' prefixes, then a literal.
        while (true) {
            pos = skipBlanks(line, pos);
            if (pos == line.len) return error.SyntaxError;
            switch (line[pos]) {
                '-' => try self.ops.append(gpa, .negate),
                '(' => try self.ops.append(gpa, .open),
                '0'...'9' => break,
                else => return error.SyntaxError,
            }
            pos += 1;
        }
        const literal = try parseLiteral(line, &pos);
        try self.values.append(gpa, literal);
        try self.applyNegations();

        // Operator position: closing parentheses, then a binary operator or the end.
        while (true) {
            pos = skipBlanks(line, pos);
            if (pos == line.len) return self.finish();
            const c = line[pos];
            pos += 1;
            if (c == ')') {
                try self.closeParen();
                continue;
            }
            const op = Op.fromByte(c) orelse return error.SyntaxError;
            while (self.ops.items.len > 0 and
                self.ops.items[self.ops.items.len - 1].precedence() >= op.precedence())
            {
                try self.reduce();
            }
            try self.ops.append(gpa, op);
            break;
        }
    }
}

fn finish(self: *Evaluator) Error!i64 {
    while (self.ops.items.len > 0) {
        if (self.ops.items[self.ops.items.len - 1] == .open) return error.SyntaxError;
        try self.reduce();
    }
    std.debug.assert(self.values.items.len == 1);
    return self.values.items[0];
}

fn closeParen(self: *Evaluator) Error!void {
    while (true) {
        const top = self.ops.getLastOrNull() orelse return error.SyntaxError;
        if (top == .open) break;
        try self.reduce();
    }
    _ = self.ops.pop();
    try self.applyNegations();
}

/// Applies the unary minus operators that directly precede the operand just completed.
fn applyNegations(self: *Evaluator) Error!void {
    while (self.ops.getLastOrNull() == .negate) {
        _ = self.ops.pop();
        const value = &self.values.items[self.values.items.len - 1];
        value.* = try negate(value.*);
    }
}

/// Pops one binary operator and its two operands, pushing the result.
fn reduce(self: *Evaluator) Error!void {
    const op = self.ops.pop().?;
    const right = self.values.pop().?;
    const left = &self.values.items[self.values.items.len - 1];
    left.* = try apply(op, left.*, right);
}

fn apply(op: Op, left: i64, right: i64) Error!i64 {
    return switch (op) {
        .add => std.math.add(i64, left, right),
        .sub => std.math.sub(i64, left, right),
        .mul => std.math.mul(i64, left, right),
        .div => {
            if (right == 0) return error.DivisionByZero;
            if (left == std.math.minInt(i64) and right == -1) return error.Overflow;
            return @divTrunc(left, right);
        },
        .rem => {
            if (right == 0) return error.DivisionByZero;
            // The remainder is always 0 here; avoids the overflowing minInt / -1.
            if (right == -1) return 0;
            return @rem(left, right);
        },
        .negate, .open => unreachable,
    };
}

fn negate(value: i64) Error!i64 {
    return std.math.negate(value);
}

fn parseLiteral(line: []const u8, pos: *usize) Error!i64 {
    const start = pos.*;
    var end = start;
    while (end < line.len and std.ascii.isDigit(line[end])) end += 1;
    pos.* = end;
    var value: i64 = 0;
    for (line[start..end]) |digit| {
        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, digit - '0');
    }
    return value;
}

fn skipBlanks(line: []const u8, start: usize) usize {
    var pos = start;
    while (pos < line.len and isBlank(line[pos])) pos += 1;
    return pos;
}

pub fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn expectValue(expected: i64, line: []const u8) !void {
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, try evaluator.evaluate(std.testing.allocator, line));
}

fn expectFailure(expected: Error, line: []const u8) !void {
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(std.testing.allocator);
    try std.testing.expectError(expected, evaluator.evaluate(std.testing.allocator, line));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(2, "100 / 10 / 5");
    try expectValue(42, " \t42\t ");
}

test "division truncates and remainder follows the dividend" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % (2 - 2)");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-6, "-2 * 3");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
}

test "overflow" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "syntax errors" {
    for ([_][]const u8{ "", "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 - - ", "1\r", "2 ** 3", "(1)(2)" }) |line| {
        try expectFailure(error.SyntaxError, line);
    }
}

test "deep nesting does not recurse" {
    const depth = 100_000;
    const line = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(line);
    @memset(line[0..depth], '(');
    line[depth] = '7';
    @memset(line[depth + 1 ..], ')');
    try expectValue(7, line);
}
