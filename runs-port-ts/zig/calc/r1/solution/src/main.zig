//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads expressions from standard input, one per line, and prints each
//! value (or `error`) on its own line. See SPEC.md for the grammar and
//! semantics.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Any condition that makes a line evaluate to `error`.
pub const CalcError = error{
    Syntax,
    Unbalanced,
    MissingOperand,
    DivisionByZero,
    Overflow,
};

pub const EvalError = CalcError || Allocator.Error;

const Op = enum {
    lparen,
    add,
    sub,
    mul,
    div,
    rem,
    neg,

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

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn applyBinary(op: Op, a: i64, b: i64) CalcError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => blk: {
            if (b == 0) return error.DivisionByZero;
            if (a == std.math.minInt(i64) and b == -1) return error.Overflow;
            break :blk @divTrunc(a, b);
        },
        .rem => blk: {
            if (b == 0) return error.DivisionByZero;
            // The remainder of minInt / -1 is 0 even though the quotient overflows.
            if (b == -1) break :blk 0;
            break :blk @rem(a, b);
        },
        .lparen, .neg => unreachable,
    };
}

/// Operator-precedence (shunting-yard) evaluator with explicit stacks, so
/// deeply nested input cannot overflow the call stack. The stacks are reused
/// across lines to avoid repeated allocation.
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

    fn reduceTop(self: *Evaluator) CalcError!void {
        const op = self.ops.pop().?;
        switch (op) {
            .lparen => unreachable,
            .neg => {
                const top = &self.values.items[self.values.items.len - 1];
                top.* = try std.math.negate(top.*);
            },
            else => {
                const b = self.values.pop().?;
                const top = &self.values.items[self.values.items.len - 1];
                top.* = try applyBinary(op, top.*, b);
            },
        }
    }

    fn topOp(self: *const Evaluator) ?Op {
        return self.ops.getLastOrNull();
    }

    /// Evaluates one expression line.
    pub fn evaluate(self: *Evaluator, line: []const u8) EvalError!i64 {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (isBlank(c)) {
                i += 1;
                continue;
            }

            if (expect_operand) {
                switch (c) {
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        const value = std.fmt.parseInt(i64, line[start..i], 10) catch
                            return error.Overflow;
                        try self.values.append(self.gpa, value);
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.Syntax,
                }
                i += 1;
                continue;
            }

            if (c == ')') {
                while (self.topOp()) |op| {
                    if (op == .lparen) break;
                    try self.reduceTop();
                } else return error.Unbalanced;
                _ = self.ops.pop();
            } else if (Op.fromBinary(c)) |op| {
                const prec = op.precedence();
                while (self.topOp()) |top| {
                    if (top.precedence() < prec) break;
                    try self.reduceTop();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.MissingOperand;
        while (self.topOp()) |op| {
            if (op == .lparen) return error.Unbalanced;
            try self.reduceTop();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }
};

fn isBlankLine(line: []const u8) bool {
    for (line) |c| {
        if (!isBlank(c)) return false;
    }
    return true;
}

/// Evaluates every line of `input`, writing one result line per non-blank
/// input line to `out`.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlankLine(line)) continue;
        if (evaluator.evaluate(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            else => try out.writeAll("error\n"),
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    try run(gpa, input, &stdout.interface);
    try stdout.interface.flush();
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n", "7\n-3\nerror\nerror\n");
}

test "division and remainder" {
    try expectOutput("7 / 2\n-7 % 3\n7 % -3\n0 / 5\n1 / 0\n5 % 0\n", "3\n-1\n1\n0\nerror\nerror\n");
}

test "int64 boundaries" {
    try expectOutput(
        "(-9223372036854775807 - 1) % -1\n" ++
            "(-9223372036854775807 - 1) / -1\n" ++
            "-9223372036854775808\n" ++
            "-(-9223372036854775807 - 1)\n" ++
            "9223372036854775808\n" ++
            "-9223372036854775807 - 1\n" ++
            "3037000499 * 3037000499\n" ++
            "000000000000000000000000007\n",
        "0\nerror\nerror\nerror\nerror\n-9223372036854775808\n9223372030926249001\n7\n",
    );
}

test "syntax errors and blank lines" {
    try expectOutput("1 +\nabc\n()\n1 2\n+1\n\n  42  \n\t\n1+1\n)\n1)\n((1)\n1\r\n", "error\nerror\nerror\nerror\nerror\n42\n2\nerror\nerror\nerror\nerror\n");
}

test "unary minus" {
    try expectOutput("--5\n2 * -3\n1 - -2\n-(2 + 3)\n-2 * 3 % 4\n", "5\n-6\n3\n-5\n-2\n");
}
