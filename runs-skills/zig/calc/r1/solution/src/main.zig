//! calc: evaluates one 64-bit signed integer expression per line of stdin.
//!
//! Evaluation uses an explicit operator/operand stack (shunting-yard) rather
//! than recursion, so arbitrarily deep nesting cannot overflow the call stack.

const std = @import("std");
const Io = std.Io;
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

/// Reusable evaluator; keeps its stacks between lines to avoid reallocations.
pub const Evaluator = struct {
    ops: std.ArrayList(Op) = .empty,
    values: std.ArrayList(i64) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.ops.deinit(gpa);
        self.values.deinit(gpa);
    }

    /// Evaluates `line`. Returns null if the line is blank (only spaces/tabs).
    pub fn eval(self: *Evaluator, gpa: Allocator, line: []const u8) EvalError!?i64 {
        self.ops.clearRetainingCapacity();
        self.values.clearRetainingCapacity();

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
                if (self.ops.pop() == null) return error.Syntax;
            } else if (Op.fromByte(c)) |op| {
                // Left-associative: reduce everything binding at least as tightly.
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
            if (op.precedence() <= floor) return;
            _ = self.ops.pop();
            const vals = &self.values.items;
            if (op == .neg) {
                const top = &vals.*[vals.len - 1];
                top.* = try negate(top.*);
            } else {
                const rhs = self.values.pop().?;
                const lhs = &vals.*[vals.len - 1];
                lhs.* = try apply(op, lhs.*, rhs);
            }
        }
    }
};

fn parseNumber(digits: []const u8) EvalError!i64 {
    var n: i64 = 0;
    for (digits) |d| {
        const m = @mulWithOverflow(n, 10);
        if (m[1] != 0) return error.Overflow;
        const a = @addWithOverflow(m[0], @as(i64, d - '0'));
        if (a[1] != 0) return error.Overflow;
        n = a[0];
    }
    return n;
}

fn negate(x: i64) EvalError!i64 {
    if (x == std.math.minInt(i64)) return error.Overflow;
    return -x;
}

fn apply(op: Op, a: i64, b: i64) EvalError!i64 {
    const r = switch (op) {
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
    if (r[1] != 0) return error.Overflow;
    return r[0];
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
        if (result) |v| try stdout.print("{d}\n", .{v});
    }
    try stdout.flush();
}

fn expectEval(expected: ?i64, line: []const u8) !void {
    var e: Evaluator = .{};
    defer e.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, try e.eval(std.testing.allocator, line));
}

fn expectFail(expected: EvalError, line: []const u8) !void {
    var e: Evaluator = .{};
    defer e.deinit(std.testing.allocator);
    try std.testing.expectError(expected, e.eval(std.testing.allocator, line));
}

test "arithmetic and precedence" {
    try expectEval(7, "1 + 2 * 3");
    try expectEval(9, "(1 + 2) * 3");
    try expectEval(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectEval(3, "10 - 4 - 3");
    try expectEval(-3, "-7 / 2");
    try expectEval(-1, "-7 % 3");
    try expectEval(1, "7 % -3");
    try expectEval(5, "--5");
    try expectEval(-6, "2 * -3");
    try expectEval(-5, "-(2 + 3)");
    try expectEval(0, "(-9223372036854775807 - 1) % -1");
    try expectEval(std.math.minInt(i64), "-9223372036854775807 - 1");
    try expectEval(null, " \t ");
}

test "errors" {
    try expectFail(error.Syntax, "(1 + 2");
    try expectFail(error.Syntax, "1 +");
    try expectFail(error.Syntax, "()");
    try expectFail(error.Syntax, "1 2");
    try expectFail(error.Syntax, "+1");
    try expectFail(error.Syntax, "1)");
    try expectFail(error.Syntax, "abc");
    try expectFail(error.DivisionByZero, "5 % 0");
    try expectFail(error.Overflow, "9223372036854775807 + 1");
    try expectFail(error.Overflow, "-9223372036854775808");
    try expectFail(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFail(error.Overflow, "-(-9223372036854775807 - 1)");
}
