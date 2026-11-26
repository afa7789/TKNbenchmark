//! 64-bit signed integer expression evaluator.
//!
//! Uses an iterative operator-precedence (shunting-yard) evaluator so that
//! deeply nested input cannot overflow the call stack. It accepts exactly:
//!
//!   expr    := term    (('+' | '-') term)*
//!   term    := unary   (('*' | '/' | '%') unary)*
//!   unary   := '-' unary | primary
//!   primary := NUMBER | '(' expr ')'

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
};

pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    pub fn eval(self: *Evaluator, gpa: Allocator, src: []const u8) EvalError!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (true) {
            while (i < src.len and (src[i] == ' ' or src[i] == '\t')) i += 1;
            if (i == src.len) break;
            const c = src[i];
            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(gpa, .neg),
                    '(' => try self.ops.append(gpa, .lparen),
                    '0'...'9' => {
                        var n: i64 = 0;
                        while (i < src.len and std.ascii.isDigit(src[i])) : (i += 1) {
                            n = try checked(@mulWithOverflow(n, 10));
                            n = try checked(@addWithOverflow(n, src[i] - '0'));
                        }
                        try self.values.append(gpa, n);
                        expect_operand = false;
                        continue;
                    },
                    else => return error.Syntax,
                }
            } else {
                const op: Op = switch (c) {
                    '+' => .add,
                    '-' => .sub,
                    '*' => .mul,
                    '/' => .div,
                    '%' => .rem,
                    ')' => {
                        try self.reduceWhile(0);
                        if (self.ops.pop() == null) return error.Syntax;
                        i += 1;
                        continue;
                    },
                    else => return error.Syntax,
                };
                // Left-associative: reduce everything that binds at least as tightly.
                try self.reduceWhile(op.precedence());
                try self.ops.append(gpa, op);
                expect_operand = true;
            }
            i += 1;
        }
        if (expect_operand) return error.Syntax;
        try self.reduceWhile(0);
        if (self.ops.items.len != 0) return error.Syntax; // unmatched '('
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    /// Applies stacked operators whose precedence is at least `min`, stopping at '('.
    fn reduceWhile(self: *Evaluator, min: u8) EvalError!void {
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen or top.precedence() < min) return;
            _ = self.ops.pop();
            try self.apply(top);
        }
    }

    fn apply(self: *Evaluator, op: Op) EvalError!void {
        const vals = &self.values;
        if (op == .neg) {
            const a = &vals.items[vals.items.len - 1];
            a.* = try checked(@subWithOverflow(0, a.*));
            return;
        }
        const b = vals.pop().?;
        const a = &vals.items[vals.items.len - 1];
        a.* = switch (op) {
            .add => try checked(@addWithOverflow(a.*, b)),
            .sub => try checked(@subWithOverflow(a.*, b)),
            .mul => try checked(@mulWithOverflow(a.*, b)),
            .div => blk: {
                if (b == 0) return error.DivisionByZero;
                if (b == -1 and a.* == std.math.minInt(i64)) return error.Overflow;
                break :blk @divTrunc(a.*, b);
            },
            .rem => blk: {
                if (b == 0) return error.DivisionByZero;
                if (b == -1) break :blk 0;
                break :blk @rem(a.*, b);
            },
            .neg, .lparen => unreachable,
        };
    }
};

fn checked(result: struct { i64, u1 }) error{Overflow}!i64 {
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

/// Evaluates each line of `input`, printing its value or `error`; blank lines print nothing.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t").len == 0) continue;
        if (evaluator.eval(gpa, line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
}

fn expectEval(src: []const u8, expected: EvalError!i64) !void {
    var e: Evaluator = .{};
    defer e.deinit(std.testing.allocator);
    const got = e.eval(std.testing.allocator, src);
    if (expected) |v| {
        try std.testing.expectEqual(v, try got);
    } else |_| {
        _ = got catch return;
        return error.TestExpectedError;
    }
}

test "arithmetic and precedence" {
    try expectEval("1 + 2 * 3", 7);
    try expectEval("(1 + 2) * 3", 9);
    try expectEval("1 + 2 * 3 - 4 / 2 % 3", 5);
    try expectEval("10 - 4 - 3", 3);
    try expectEval("-7 / 2", -3);
    try expectEval("-7 % 3", -1);
    try expectEval("7 % -3", 1);
    try expectEval("--5", 5);
    try expectEval("1 - -2", 3);
    try expectEval("-(2 + 3)", -5);
    try expectEval("((((7))))", 7);
}

test "limits" {
    try expectEval("-9223372036854775807 - 1", std.math.minInt(i64));
    try expectEval("(-9223372036854775807 - 1) % -1", 0);
    try expectEval("(-9223372036854775807 - 1) / -1", error.Overflow);
    try expectEval("-(-9223372036854775807 - 1)", error.Overflow);
    try expectEval("9223372036854775807 + 1", error.Overflow);
    try expectEval("9223372036854775808", error.Overflow);
    try expectEval("-9223372036854775808", error.Overflow);
    try expectEval("1 / 0", error.DivisionByZero);
    try expectEval("5 % 0", error.DivisionByZero);
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 -", "- ", "2 * * 3", "1\r" }) |src| {
        try expectEval(src, error.Syntax);
    }
}
