//! `calc`: evaluate one signed 64-bit integer expression per input line.
//!
//! Parsing is iterative (operator precedence with explicit stacks), so deeply
//! nested input cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ Syntax, DivisionByZero, Overflow };

const Op = enum(u8) {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    /// An open parenthesis; acts as a barrier on the operator stack.
    paren,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .paren => 0,
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

pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(e: *Evaluator, gpa: Allocator) void {
        e.values.deinit(gpa);
        e.ops.deinit(gpa);
        e.* = undefined;
    }

    /// Evaluates `src`, which must contain exactly one expression.
    pub fn eval(e: *Evaluator, gpa: Allocator, src: []const u8) (Error || Allocator.Error)!i64 {
        e.values.clearRetainingCapacity();
        e.ops.clearRetainingCapacity();

        var i: usize = 0;
        var expect_operand = true;
        while (true) {
            while (i < src.len and isBlank(src[i])) i += 1;
            if (i == src.len) break;
            const c = src[i];

            if (expect_operand) {
                switch (c) {
                    '-' => try e.ops.append(gpa, .neg),
                    '(' => try e.ops.append(gpa, .paren),
                    '0'...'9' => {
                        const start = i;
                        while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
                        const value = std.fmt.parseInt(i64, src[start..i], 10) catch return error.Overflow;
                        try e.values.append(gpa, value);
                        expect_operand = false;
                        continue;
                    },
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                while (true) {
                    const op = e.ops.pop() orelse return error.Syntax;
                    if (op == .paren) break;
                    try e.apply(op);
                }
            } else if (Op.fromBinary(c)) |op| {
                try e.reduce(op.precedence());
                try e.ops.append(gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax;
        try e.reduce(1);
        if (e.ops.items.len != 0) return error.Syntax; // unmatched '('
        std.debug.assert(e.values.items.len == 1);
        return e.values.items[0];
    }

    /// Applies stacked operators whose precedence is at least `min` (left associativity).
    fn reduce(e: *Evaluator, min: u8) Error!void {
        while (e.ops.getLastOrNull()) |op| {
            if (op.precedence() < min) break;
            _ = e.ops.pop();
            try e.apply(op);
        }
    }

    fn apply(e: *Evaluator, op: Op) Error!void {
        const values = &e.values;
        if (op == .neg) {
            const a = &values.items[values.items.len - 1];
            a.* = try std.math.negate(a.*);
            return;
        }
        const b = values.pop().?;
        const a = &values.items[values.items.len - 1];
        a.* = try binary(op, a.*, b);
    }
};

fn binary(op: Op, a: i64, b: i64) Error!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => if (b == 0)
            error.DivisionByZero
        else if (a == std.math.minInt(i64) and b == -1)
            error.Overflow
        else
            @divTrunc(a, b),
        .rem => if (b == 0)
            error.DivisionByZero
        else if (b == -1)
            0 // Avoids the trapping minInt % -1; the remainder is always 0.
        else
            @rem(a, b),
        .neg, .paren => unreachable,
    };
}

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Evaluates every line of `input`, writing a value or `error` per non-blank line.
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

fn expectEval(src: []const u8, expected: Error!i64) !void {
    const gpa = std.testing.allocator;
    var e: Evaluator = .{};
    defer e.deinit(gpa);
    try std.testing.expectEqual(expected, e.eval(gpa, src));
}

test "arithmetic and precedence" {
    try expectEval("1 + 2 * 3", 7);
    try expectEval("(1 + 2) * 3", 9);
    try expectEval("1 + 2 * 3 - 4 / 2 % 3", 5);
    try expectEval("10 - 4 - 3", 3);
    try expectEval("--5", 5);
    try expectEval("-(2 + 3)", -5);
    try expectEval("2 * -3", -6);
    try expectEval("-2 * -3", 6);
    try expectEval("- 3 - - 2", -1);
}

test "division semantics" {
    try expectEval("-7 / 2", -3);
    try expectEval("-7 % 3", -1);
    try expectEval("7 % -3", 1);
    try expectEval("1 / 0", error.DivisionByZero);
    try expectEval("5 % 0", error.DivisionByZero);
    try expectEval("(-9223372036854775807 - 1) % -1", 0);
    try expectEval("(-9223372036854775807 - 1) / -1", error.Overflow);
}

test "overflow" {
    try expectEval("9223372036854775807 + 1", error.Overflow);
    try expectEval("9223372036854775808", error.Overflow);
    try expectEval("-9223372036854775808", error.Overflow);
    try expectEval("-(-9223372036854775807 - 1)", error.Overflow);
    try expectEval("3037000500 * 3037000500", error.Overflow);
    try expectEval("00009223372036854775807", 9223372036854775807);
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 (2)", "2 -", "1 ** 2", "1\r" }) |src| {
        try expectEval(src, error.Syntax);
    }
}

test "deep nesting" {
    const gpa = std.testing.allocator;
    const depth = 100_000;
    const src = try gpa.alloc(u8, 2 * depth + 1);
    defer gpa.free(src);
    @memset(src[0..depth], '(');
    src[depth] = '7';
    @memset(src[depth + 1 ..], ')');
    try expectEval(src, 7);
}
