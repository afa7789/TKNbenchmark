//! calc: evaluates one signed 64-bit integer expression per line of stdin.
//!
//! The parser is an operator-precedence (shunting-yard) evaluator driven by
//! explicit stacks, so arbitrarily deep nesting cannot overflow the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EvalError = error{ Syntax, DivisionByZero, Overflow } || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
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

/// Reusable evaluator; keeps its stacks allocated between lines.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
    }

    /// Evaluates `line`. Returns null if the line contains only blanks.
    pub fn eval(self: *Evaluator, gpa: Allocator, line: []const u8) EvalError!?i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var seen_token = false;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (c == ' ' or c == '\t') {
                i += 1;
                continue;
            }
            seen_token = true;
            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(gpa, .neg),
                    '(' => try self.ops.append(gpa, .lparen),
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        try self.values.append(gpa, try parseNumber(line[start..i]));
                        expect_operand = false;
                        continue;
                    },
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                try self.reduceWhile(0);
                if (self.ops.pop() != .lparen) return error.Syntax;
            } else if (Op.fromBinary(c)) |op| {
                // Left associativity: reduce everything binding at least as tightly.
                try self.reduceWhile(op.precedence() - 1);
                try self.ops.append(gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (!seen_token) return null;
        if (expect_operand) return error.Syntax;
        try self.reduceWhile(0);
        if (self.ops.items.len != 0) return error.Syntax; // unmatched '('
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    /// Applies stacked operators whose precedence exceeds `floor`.
    fn reduceWhile(self: *Evaluator, floor: u8) EvalError!void {
        while (self.ops.getLastOrNull()) |op| {
            if (op.precedence() <= floor) break;
            _ = self.ops.pop();
            if (op == .neg) {
                const v = &self.values.items[self.values.items.len - 1];
                v.* = try negate(v.*);
            } else {
                const rhs = self.values.pop().?;
                const lhs = &self.values.items[self.values.items.len - 1];
                lhs.* = try apply(op, lhs.*, rhs);
            }
        }
    }
};

fn parseNumber(digits: []const u8) error{Overflow}!i64 {
    var n: i64 = 0;
    for (digits) |d| {
        n = try std.math.mul(i64, n, 10);
        n = try std.math.add(i64, n, d - '0');
    }
    return n;
}

fn negate(v: i64) error{Overflow}!i64 {
    return std.math.negate(v);
}

fn apply(op: Op, a: i64, b: i64) error{ DivisionByZero, Overflow }!i64 {
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
            if (b == -1) return 0;
            return @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;

    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const result = evaluator.eval(gpa, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => {
                try out.writeAll("error\n");
                continue;
            },
        };
        if (result) |value| try out.print("{d}\n", .{value});
    }
    try out.flush();
}

fn expectEval(line: []const u8, expected: EvalError!?i64) !void {
    var e: Evaluator = .{};
    defer e.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, e.eval(std.testing.allocator, line));
}

test "arithmetic and precedence" {
    try expectEval("1 + 2 * 3", 7);
    try expectEval("(1 + 2) * 3", 9);
    try expectEval("10 - 4 - 3", 3);
    try expectEval("1 + 2 * 3 - 4 / 2 % 3", 5);
    try expectEval("-7 / 2", -3);
    try expectEval("-7 % 3", -1);
    try expectEval("7 % -3", 1);
    try expectEval("--5", 5);
    try expectEval("-(2 + 3)", -5);
    try expectEval("2 * -3", -6);
    try expectEval("  \t ", null);
    try expectEval("", null);
}

test "errors" {
    try expectEval("(1 + 2", error.Syntax);
    try expectEval("1 + 2)", error.Syntax);
    try expectEval("()", error.Syntax);
    try expectEval("1 2", error.Syntax);
    try expectEval("+1", error.Syntax);
    try expectEval("1 +", error.Syntax);
    try expectEval("1 / 0", error.DivisionByZero);
    try expectEval("5 % 0", error.DivisionByZero);
    try expectEval("9223372036854775807 + 1", error.Overflow);
    try expectEval("9223372036854775808", error.Overflow);
    try expectEval("-9223372036854775808", error.Overflow);
    try expectEval("(-9223372036854775807 - 1) / -1", error.Overflow);
    try expectEval("-(-9223372036854775807 - 1)", error.Overflow);
}

test "boundaries" {
    try expectEval("(-9223372036854775807 - 1) % -1", 0);
    try expectEval("-9223372036854775807 - 1", std.math.minInt(i64));
    try expectEval("00012", 12);
}
