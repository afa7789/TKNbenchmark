//! Evaluates one line of the calc grammar (see SPEC.md) over signed 64-bit integers.
//!
//! Parsing and evaluation happen in a single pass driven by explicit operand and
//! operator stacks (shunting-yard), so neither deeply nested parentheses nor long
//! chains of unary minus can exhaust the call stack. The stacks are kept between
//! calls, so evaluating many lines allocates only when a line is deeper than any
//! seen before.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

gpa: Allocator,
operands: std.ArrayList(i64) = .empty,
operators: std.ArrayList(Operator) = .empty,

/// Reasons an expression has no value. Any of them prints `error`.
pub const EvalError = error{ SyntaxError, DivisionByZero, Overflow };

pub const Error = EvalError || Allocator.Error;

const Operator = enum {
    add,
    sub,
    mul,
    div,
    rem,
    negate,
    /// Marks an open parenthesis; never applied, only matched by `)`.
    open_paren,

    /// Binding strength; operators of higher precedence are applied first.
    fn precedence(op: Operator) u8 {
        return switch (op) {
            .open_paren => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .negate => 3,
        };
    }

    fn fromBinary(c: u8) ?Operator {
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

pub fn deinit(self: *Evaluator) void {
    self.operands.deinit(self.gpa);
    self.operators.deinit(self.gpa);
    self.* = undefined;
}

/// Returns true if `line` holds only spaces and tabs, i.e. produces no output.
pub fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (!isSpace(c)) return false;
    }
    return true;
}

/// Evaluates `expr`, which must not contain the line terminator.
pub fn eval(self: *Evaluator, expr: []const u8) Error!i64 {
    self.operands.clearRetainingCapacity();
    self.operators.clearRetainingCapacity();

    // The grammar alternates operands and binary operators; this tracks which
    // one the next token must be.
    var expect_operand = true;
    var i: usize = 0;
    while (i < expr.len) {
        const c = expr[i];
        if (isSpace(c)) {
            i += 1;
            continue;
        }
        if (expect_operand) {
            switch (c) {
                '0'...'9' => {
                    const end = std.mem.indexOfNonePos(u8, expr, i, "0123456789") orelse expr.len;
                    try self.operands.append(self.gpa, try parseLiteral(expr[i..end]));
                    i = end;
                    expect_operand = false;
                    continue;
                },
                '-' => try self.operators.append(self.gpa, .negate),
                '(' => try self.operators.append(self.gpa, .open_paren),
                else => return error.SyntaxError,
            }
        } else if (Operator.fromBinary(c)) |op| {
            // Left associativity: apply pending operators of equal or higher precedence.
            while (self.topOperator()) |top| {
                if (top.precedence() < op.precedence()) break;
                try self.applyTop();
            }
            try self.operators.append(self.gpa, op);
            expect_operand = true;
        } else if (c == ')') {
            while (true) {
                const top = self.topOperator() orelse return error.SyntaxError;
                if (top == .open_paren) break;
                try self.applyTop();
            }
            _ = self.operators.pop();
        } else {
            return error.SyntaxError;
        }
        i += 1;
    }

    if (expect_operand) return error.SyntaxError;
    while (self.topOperator()) |top| {
        if (top == .open_paren) return error.SyntaxError;
        try self.applyTop();
    }
    std.debug.assert(self.operands.items.len == 1);
    return self.operands.items[0];
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn topOperator(self: *const Evaluator) ?Operator {
    return self.operators.getLastOrNull();
}

/// Pops the top operator and its operands and pushes the result. The
/// alternation enforced by `eval` guarantees the operands are present.
fn applyTop(self: *Evaluator) EvalError!void {
    const op = self.operators.pop().?;
    const operands = &self.operands;
    if (op == .negate) {
        const top = &operands.items[operands.items.len - 1];
        top.* = try std.math.negate(top.*);
        return;
    }
    const rhs = operands.pop().?;
    const lhs = &operands.items[operands.items.len - 1];
    lhs.* = try applyBinary(op, lhs.*, rhs);
}

fn applyBinary(op: Operator, lhs: i64, rhs: i64) EvalError!i64 {
    return switch (op) {
        .add => std.math.add(i64, lhs, rhs),
        .sub => std.math.sub(i64, lhs, rhs),
        .mul => std.math.mul(i64, lhs, rhs),
        .div => std.math.divTrunc(i64, lhs, rhs),
        .rem => {
            if (rhs == 0) return error.DivisionByZero;
            // minInt % -1 is mathematically 0 but traps in hardware.
            if (rhs == -1) return 0;
            return @rem(lhs, rhs);
        },
        .negate, .open_paren => unreachable,
    };
}

/// Parses a non-empty run of decimal digits.
fn parseLiteral(digits: []const u8) EvalError!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, d - '0');
    }
    return value;
}

fn expectValue(expected: i64, expr: []const u8) !void {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    try std.testing.expectEqual(expected, try evaluator.eval(expr));
}

fn expectFailure(expected: EvalError, expr: []const u8) !void {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    try std.testing.expectError(expected, evaluator.eval(expr));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(1, "100 / 10 / 10");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(42, "\t 42 ");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-1, "- 2 + 1");
    try expectValue(6, "-2 * -3");
}

test "division truncates toward zero" {
    try expectValue(-3, "-7 / 2");
    try expectValue(3, "7 / 2");
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
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "4611686018427387904 * 2");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 (2)", "-", "1 ** 2", "1\r" }) |expr| {
        try expectFailure(error.SyntaxError, expr);
    }
}

test "deep nesting does not recurse" {
    const depth = 100_000;
    const expr = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(expr);
    @memset(expr[0..depth], '(');
    expr[depth] = '7';
    @memset(expr[depth + 1 ..], ')');
    try expectValue(7, expr);
}

test isBlank {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank(" 1 "));
}
