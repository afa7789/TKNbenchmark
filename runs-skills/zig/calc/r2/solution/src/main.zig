//! calc: a line-oriented 64-bit signed integer expression evaluator.
//!
//! Each input line is parsed and evaluated with an iterative operator-precedence
//! (shunting-yard) algorithm, so arbitrarily deep nesting cannot overflow the
//! call stack.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const EvalError = error{
    Syntax,
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
    lparen,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
        };
    }

    fn fromBinaryChar(c: u8) ?Op {
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

/// Reusable evaluator; keeps its stacks' capacity across lines.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Evaluates one expression. The input must not be blank.
    pub fn eval(self: *Evaluator, gpa: Allocator, src: []const u8) EvalError!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (i < src.len) {
            const c = src[i];
            if (c == ' ' or c == '\t') {
                i += 1;
                continue;
            }
            if (expect_operand) {
                switch (c) {
                    '-' => try self.ops.append(gpa, .neg),
                    '(' => try self.ops.append(gpa, .lparen),
                    '0'...'9' => {
                        const start = i;
                        while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
                        try self.values.append(gpa, try parseLiteral(src[start..i]));
                        expect_operand = false;
                        continue;
                    },
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                while (true) {
                    const top = self.ops.pop() orelse return error.Syntax;
                    if (top == .lparen) break;
                    try self.apply(top);
                }
            } else {
                const op = Op.fromBinaryChar(c) orelse return error.Syntax;
                // All binary operators are left-associative.
                while (self.ops.items.len > 0) {
                    const top = self.ops.items[self.ops.items.len - 1];
                    if (top.precedence() < op.precedence()) break;
                    _ = self.ops.pop();
                    try self.apply(top);
                }
                try self.ops.append(gpa, op);
                expect_operand = true;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.pop()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.apply(top);
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    fn apply(self: *Evaluator, op: Op) EvalError!void {
        const vals = &self.values;
        if (op == .neg) {
            const top = &vals.items[vals.items.len - 1];
            top.* = try negate(top.*);
            return;
        }
        const b = vals.pop().?;
        const a = &vals.items[vals.items.len - 1];
        a.* = try binary(op, a.*, b);
    }
};

fn parseLiteral(digits: []const u8) error{Overflow}!i64 {
    var n: i64 = 0;
    for (digits) |d| {
        n = std.math.mul(i64, n, 10) catch return error.Overflow;
        n = std.math.add(i64, n, d - '0') catch return error.Overflow;
    }
    return n;
}

fn negate(x: i64) error{Overflow}!i64 {
    return std.math.negate(x) catch error.Overflow;
}

fn binary(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b) catch error.Overflow,
        .sub => std.math.sub(i64, a, b) catch error.Overflow,
        .mul => std.math.mul(i64, a, b) catch error.Overflow,
        .div => blk: {
            if (b == 0) return error.DivisionByZero;
            if (a == std.math.minInt(i64) and b == -1) return error.Overflow;
            break :blk @divTrunc(a, b);
        },
        .rem => blk: {
            if (b == 0) return error.DivisionByZero;
            if (b == -1) break :blk 0;
            break :blk @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

fn isBlank(line: []const u8) bool {
    for (line) |c| if (c != ' ' and c != '\t') return false;
    return true;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const w = &stdout.interface;

    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlank(line)) continue;
        if (evaluator.eval(gpa, line)) |value| {
            try w.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try w.writeAll("error\n"),
        }
    }
    try w.flush();
}

fn expectValue(expected: i64, src: []const u8) !void {
    var e: Evaluator = .{};
    defer e.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, try e.eval(std.testing.allocator, src));
}

fn expectFailure(expected: EvalError, src: []const u8) !void {
    var e: Evaluator = .{};
    defer e.deinit(std.testing.allocator);
    try std.testing.expectError(expected, e.eval(std.testing.allocator, src));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(1, "100 / 10 / 10");
    try expectValue(10, "--5*2");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(3, "1 - -2");
}

test "division semantics" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % 0");
}

test "overflow" {
    try expectValue(std.math.maxInt(i64), "9223372036854775807");
    try expectValue(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 -", "*1", "1\r" }) |src| {
        try expectFailure(error.Syntax, src);
    }
}

test "deep nesting" {
    const depth = 100_000;
    var buf: [2 * depth + 1]u8 = undefined;
    @memset(buf[0..depth], '(');
    buf[depth] = '7';
    @memset(buf[depth + 1 ..], ')');
    try expectValue(7, &buf);
}
