//! calc: evaluates one signed 64-bit integer expression per line of stdin.
//!
//! The parser is an iterative operator-precedence (shunting-yard) evaluator,
//! so arbitrarily deep nesting cannot overflow the native call stack.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const EvalError = error{
    Syntax,
    DivisionByZero,
    Overflow,
};

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

/// Reusable evaluator; keeps its stacks allocated between lines.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Evaluates `line`. Returns null if the line is blank (spaces/tabs only).
    pub fn eval(self: *Evaluator, gpa: Allocator, line: []const u8) (EvalError || Allocator.Error)!?i64 {
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
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        try self.values.append(gpa, try parseLiteral(line[start..i]));
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(gpa, .neg),
                    '(' => try self.ops.append(gpa, .lparen),
                    else => return error.Syntax,
                }
            } else {
                switch (c) {
                    ')' => {
                        while (true) {
                            const top = self.ops.pop() orelse return error.Syntax;
                            if (top == .lparen) break;
                            try self.apply(top);
                        }
                    },
                    '+', '-', '*', '/', '%' => {
                        const op: Op = switch (c) {
                            '+' => .add,
                            '-' => .sub,
                            '*' => .mul,
                            '/' => .div,
                            '%' => .rem,
                            else => unreachable,
                        };
                        try self.reduceWhile(op.precedence());
                        try self.ops.append(gpa, op);
                        expect_operand = true;
                    },
                    else => return error.Syntax,
                }
            }
            i += 1;
        }

        if (!seen_token) return null;
        if (expect_operand) return error.Syntax;

        while (self.ops.pop()) |op| {
            if (op == .lparen) return error.Syntax;
            try self.apply(op);
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    /// Applies stacked operators whose precedence is at least `min_prec`
    /// (all binary operators are left-associative).
    fn reduceWhile(self: *Evaluator, min_prec: u8) EvalError!void {
        while (self.ops.items.len > 0) {
            const top = self.ops.items[self.ops.items.len - 1];
            if (top == .lparen or top.precedence() < min_prec) break;
            _ = self.ops.pop();
            try self.apply(top);
        }
    }

    fn apply(self: *Evaluator, op: Op) EvalError!void {
        const values = &self.values;
        if (op == .neg) {
            const a = &values.items[values.items.len - 1];
            a.* = try negate(a.*);
            return;
        }
        const b = values.pop().?;
        const a = &values.items[values.items.len - 1];
        a.* = try binary(op, a.*, b);
    }
};

fn parseLiteral(digits: []const u8) EvalError!i64 {
    var acc: i64 = 0;
    for (digits) |d| {
        const mul = @mulWithOverflow(acc, 10);
        if (mul[1] != 0) return error.Overflow;
        const add = @addWithOverflow(mul[0], @as(i64, d - '0'));
        if (add[1] != 0) return error.Overflow;
        acc = add[0];
    }
    return acc;
}

fn negate(a: i64) EvalError!i64 {
    if (a == std.math.minInt(i64)) return error.Overflow;
    return -a;
}

fn binary(op: Op, a: i64, b: i64) EvalError!i64 {
    const result = switch (op) {
        .add => @addWithOverflow(a, b),
        .sub => @subWithOverflow(a, b),
        .mul => @mulWithOverflow(a, b),
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
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var in: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const input = try in.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var out: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const stdout = &out.interface;

    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const result = evaluator.eval(gpa, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => {
                try stdout.writeAll("error\n");
                continue;
            },
        };
        if (result) |value| try stdout.print("{d}\n", .{value});
    }
    try stdout.flush();
}

fn expectValue(expected: ?i64, line: []const u8) !void {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, try ev.eval(std.testing.allocator, line));
}

fn expectFailure(expected: anyerror, line: []const u8) !void {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    try std.testing.expectError(expected, ev.eval(std.testing.allocator, line));
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
    try expectValue(null, " \t ");
    try expectValue(null, "");
}

test "64-bit edges" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectValue(std.math.minInt(i64), "-4611686018427387904 * 2");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "1 % 0");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 - - ", "2 * (", "1\r" }) |line| {
        try expectFailure(error.Syntax, line);
    }
}
