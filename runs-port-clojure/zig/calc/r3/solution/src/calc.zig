//! Evaluator for signed 64-bit integer expressions.
//!
//! Grammar (spaces and tabs may appear between any two tokens):
//!
//!     expr    := term    (('+' | '-') term)*
//!     term    := unary   (('*' | '/' | '%') unary)*
//!     unary   := '-' unary | primary
//!     primary := NUMBER | '(' expr ')'
//!     NUMBER  := [0-9]+
//!
//! Parsing uses operator precedence with explicit stacks instead of
//! recursion, so nesting depth is bounded only by available memory.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    /// The line does not match the grammar.
    SyntaxError,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result does not fit in an `i64`.
    Overflow,
} || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    /// Marks an open parenthesis on the operator stack.
    lparen,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
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

/// Returns true when `line` holds nothing but spaces and tabs.
pub fn isBlank(line: []const u8) bool {
    for (line) |c| {
        if (!isSpace(c)) return false;
    }
    return true;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Reusable evaluator; its stacks keep their capacity between lines.
pub const Evaluator = struct {
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

    /// Evaluates one expression line.
    pub fn evaluate(self: *Evaluator, line: []const u8) Error!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        // True while the next token must start an operand.
        var expect_operand = true;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (isSpace(c)) {
                i += 1;
                continue;
            }
            if (expect_operand) {
                switch (c) {
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        const value = std.fmt.parseInt(i64, line[start..i], 10) catch |err| switch (err) {
                            error.Overflow => return error.Overflow,
                            error.InvalidCharacter => unreachable,
                        };
                        try self.values.append(self.gpa, value);
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.SyntaxError,
                }
            } else if (Op.binary(c)) |op| {
                // All operators are left-associative; unary minus binds tightest.
                while (self.topOp()) |top| {
                    if (top.precedence() < op.precedence()) break;
                    try self.reduce();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else if (c == ')') {
                while (true) {
                    const top = self.topOp() orelse return error.SyntaxError;
                    if (top == .lparen) break;
                    try self.reduce();
                }
                _ = self.ops.pop();
            } else {
                return error.SyntaxError;
            }
            i += 1;
        }

        if (expect_operand) return error.SyntaxError;
        while (self.topOp()) |top| {
            if (top == .lparen) return error.SyntaxError;
            try self.reduce();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    fn topOp(self: *const Evaluator) ?Op {
        return self.ops.getLastOrNull();
    }

    /// Pops the top operator and applies it to the value stack.
    fn reduce(self: *Evaluator) Error!void {
        const op = self.ops.pop().?;
        const values = self.values.items;
        if (op == .neg) {
            const a = &values[values.len - 1];
            a.* = try negate(a.*);
            return;
        }
        const b = self.values.pop().?;
        const a = &values[values.len - 2];
        a.* = try apply(op, a.*, b);
    }
};

fn negate(a: i64) Error!i64 {
    if (a == std.math.minInt(i64)) return error.Overflow;
    return -a;
}

fn apply(op: Op, a: i64, b: i64) Error!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => {
            if (b == 0) return error.DivisionByZero;
            if (a == std.math.minInt(i64) and b == -1) return error.Overflow;
            return @divTrunc(a, b);
        },
        .rem => {
            if (b == 0) return error.DivisionByZero;
            // The exact remainder is 0; avoid the overflowing division.
            if (b == -1) return 0;
            return @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

// ---------------------------------------------------------------------------
// Tests

fn expectValue(expected: i64, line: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectEqual(expected, try ev.evaluate(line));
}

fn expectFailure(expected: Error, line: []const u8) !void {
    var ev: Evaluator = .init(std.testing.allocator);
    defer ev.deinit();
    try std.testing.expectError(expected, ev.evaluate(line));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(70, "2*(3+4)*5");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(1, "8 / 4 / 2");
    try expectValue(42, "  42  ");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(3, "1 - -2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(-24, "2 * -3 * 4");
    try expectValue(-6, "-2 * 3");
    try expectValue(-9223372036854775807, "- 9223372036854775807");
}

test "division and remainder" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % 0");
}

test "overflow" {
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1\r", "1 -", "(", "2 * (3" }) |line| {
        try expectFailure(error.SyntaxError, line);
    }
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

test "blank lines" {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank(" 1 "));
}
