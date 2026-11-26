//! Streaming evaluator for signed 64-bit integer expressions.
//!
//! Grammar:
//!   expr    := term    (('+' | '-') term)*
//!   term    := unary   (('*' | '/' | '%') unary)*
//!   unary   := '-' unary | primary
//!   primary := NUMBER | '(' expr ')'
//!
//! The evaluator is an operator-precedence (shunting-yard) machine driven one
//! byte at a time, so a line never needs to be buffered and arbitrarily deep
//! nesting costs heap, not call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Reasons a line cannot be evaluated.
pub const EvalError = error{ Syntax, DivisionByZero, Overflow };

/// The result of one input line.
pub const Outcome = union(enum) {
    /// The line was empty or held only spaces and tabs.
    blank,
    value: i64,
    /// Syntax error, division by zero, or overflow.
    failure,
};

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    lparen,

    fn isBinary(op: Op) bool {
        return switch (op) {
            .add, .sub, .mul, .div, .rem => true,
            .neg, .lparen => false,
        };
    }

    fn precedence(op: Op) u8 {
        return switch (op) {
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg, .lparen => unreachable,
        };
    }
};

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Applies a binary operator with checked 64-bit semantics.
fn apply(op: Op, a: i64, b: i64) EvalError!i64 {
    const math = std.math;
    return switch (op) {
        .add => math.add(i64, a, b) catch error.Overflow,
        .sub => math.sub(i64, a, b) catch error.Overflow,
        .mul => math.mul(i64, a, b) catch error.Overflow,
        .div => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            if (a == math.minInt(i64) and b == -1) break :blk error.Overflow;
            break :blk @divTrunc(a, b);
        },
        .rem => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            // minInt % -1 is mathematically 0 but traps in hardware.
            if (b == -1) break :blk 0;
            break :blk @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

fn negate(v: i64) EvalError!i64 {
    return std.math.negate(v) catch error.Overflow;
}

pub const Evaluator = struct {
    gpa: Allocator,
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,
    expect: enum { operand, operator } = .operand,
    /// Value of the number literal currently being read, if any.
    literal: ?i64 = null,
    /// No byte other than a space or tab has been seen on this line.
    blank: bool = true,
    /// The line is already known to be an error; the rest is ignored.
    failed: bool = false,

    pub fn init(gpa: Allocator) Evaluator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Evaluator) void {
        self.values.deinit(self.gpa);
        self.ops.deinit(self.gpa);
        self.* = undefined;
    }

    /// Feeds part of the current line. `bytes` must not contain line terminators.
    pub fn feed(self: *Evaluator, bytes: []const u8) Allocator.Error!void {
        for (bytes) |c| {
            if (self.failed) return;
            if (!isBlank(c)) self.blank = false;
            self.step(c) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Syntax, error.DivisionByZero, error.Overflow => self.failed = true,
            };
        }
    }

    /// Ends the current line, returns its outcome, and readies the evaluator
    /// for the next line.
    pub fn finish(self: *Evaluator) Allocator.Error!Outcome {
        defer self.reset();
        if (self.blank) return .blank;
        if (self.failed) return .failure;
        const value = self.finalize() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Syntax, error.DivisionByZero, error.Overflow => return .failure,
        };
        return .{ .value = value };
    }

    fn reset(self: *Evaluator) void {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();
        self.expect = .operand;
        self.literal = null;
        self.blank = true;
        self.failed = false;
    }

    const StepError = EvalError || Allocator.Error;

    fn step(self: *Evaluator, c: u8) StepError!void {
        if (std.ascii.isDigit(c)) {
            const digit: i64 = c - '0';
            if (self.literal) |acc| {
                const shifted = std.math.mul(i64, acc, 10) catch return error.Overflow;
                self.literal = std.math.add(i64, shifted, digit) catch return error.Overflow;
            } else {
                if (self.expect != .operand) return error.Syntax;
                self.literal = digit;
            }
            return;
        }

        try self.endLiteral();
        switch (c) {
            ' ', '\t' => {},
            '+' => try self.binary(.add),
            '-' => switch (self.expect) {
                .operand => try self.ops.append(self.gpa, .neg),
                .operator => try self.binary(.sub),
            },
            '*' => try self.binary(.mul),
            '/' => try self.binary(.div),
            '%' => try self.binary(.rem),
            '(' => {
                if (self.expect != .operand) return error.Syntax;
                try self.ops.append(self.gpa, .lparen);
            },
            ')' => try self.closeParen(),
            else => return error.Syntax,
        }
    }

    fn endLiteral(self: *Evaluator) StepError!void {
        if (self.literal) |v| {
            self.literal = null;
            try self.pushOperand(v);
        }
    }

    /// Records a completed primary, first applying any unary minus that
    /// precedes it (unary minus binds tighter than every binary operator).
    fn pushOperand(self: *Evaluator, primary: i64) StepError!void {
        var v = primary;
        while (self.ops.items.len > 0 and self.ops.items[self.ops.items.len - 1] == .neg) {
            _ = self.ops.pop();
            v = try negate(v);
        }
        try self.values.append(self.gpa, v);
        self.expect = .operator;
    }

    fn binary(self: *Evaluator, op: Op) StepError!void {
        if (self.expect != .operator) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (!top.isBinary() or top.precedence() < op.precedence()) break;
            try self.reduce();
        }
        try self.ops.append(self.gpa, op);
        self.expect = .operand;
    }

    fn closeParen(self: *Evaluator) StepError!void {
        if (self.expect != .operator) return error.Syntax;
        while (true) {
            const top = self.ops.getLastOrNull() orelse return error.Syntax;
            if (top == .lparen) break;
            try self.reduce();
        }
        _ = self.ops.pop();
        try self.pushOperand(self.values.pop().?);
    }

    /// Pops one binary operator and its two operands, pushing the result.
    fn reduce(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        const rhs = self.values.pop().?;
        const lhs = &self.values.items[self.values.items.len - 1];
        lhs.* = try apply(op, lhs.*, rhs);
    }

    fn finalize(self: *Evaluator) StepError!i64 {
        try self.endLiteral();
        if (self.expect != .operator) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduce();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }
};

// ---------------------------------------------------------------------------
// Tests

fn evalLine(line: []const u8) !Outcome {
    var ev = Evaluator.init(std.testing.allocator);
    defer ev.deinit();
    try ev.feed(line);
    return ev.finish();
}

fn expectValue(want: i64, line: []const u8) !void {
    try std.testing.expectEqual(Outcome{ .value = want }, try evalLine(line));
}

fn expectFailure(line: []const u8) !void {
    try std.testing.expectEqual(Outcome.failure, try evalLine(line));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(1, "100 / 10 / 10");
    try expectValue(42, "  42  ");
}

test "division and remainder truncate toward zero" {
    try expectValue(-3, "-7 / 2");
    try expectValue(3, "7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure("1 / 0");
    try expectFailure("5 % 0");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-6, "-2*3");
    try expectValue(-9223372036854775807, "-9223372036854775807");
}

test "overflow" {
    try expectFailure("9223372036854775807 + 1");
    try expectFailure("9223372036854775808");
    try expectFailure("-9223372036854775808");
    try expectFailure("-(-9223372036854775807 - 1)");
    try expectFailure("(-9223372036854775807 - 1) / -1");
    try expectFailure("3037000500 * 3037000500");
    try expectValue(9223372030926249001, "3037000499 * 3037000499");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "1 (2)", "(1)2", "1\r", "-", "1 * * 2" }) |line| {
        try expectFailure(line);
    }
}

test "blank lines" {
    try std.testing.expectEqual(Outcome.blank, try evalLine(""));
    try std.testing.expectEqual(Outcome.blank, try evalLine(" \t "));
}

test "deep nesting" {
    const depth = 100_000;
    const line = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(line);
    @memset(line[0..depth], '(');
    line[depth] = '7';
    @memset(line[depth + 1 ..], ')');
    try expectValue(7, line);
}

test "evaluator is reusable across lines" {
    var ev = Evaluator.init(std.testing.allocator);
    defer ev.deinit();
    try ev.feed("(1 +");
    try std.testing.expectEqual(Outcome.failure, try ev.finish());
    try ev.feed("12");
    try ev.feed("34 - 1");
    try std.testing.expectEqual(Outcome{ .value = 1233 }, try ev.finish());
}
