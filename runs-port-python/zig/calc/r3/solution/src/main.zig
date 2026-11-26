//! calc: evaluate 64-bit signed integer expressions, one per input line.
//!
//! Each non-blank line of standard input is parsed and evaluated; its value,
//! or `error`, is written to standard output.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Any syntax, range, or arithmetic failure while evaluating an expression.
pub const CalcError = error{
    Syntax,
    Overflow,
    DivisionByZero,
};

pub const EvalError = CalcError || Allocator.Error;

const Op = enum {
    add,
    sub,
    mul,
    div,
    rem,
    neg,
    lparen,

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

    /// Binding strength; unary minus binds tighter than every binary operator.
    fn precedence(op: Op) u8 {
        return switch (op) {
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
            .lparen => 0,
        };
    }
};

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn parseLiteral(digits: []const u8) CalcError!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = try std.math.mul(i64, value, 10);
        value = try std.math.add(i64, value, d - '0');
    }
    return value;
}

fn applyBinary(op: Op, a: i64, b: i64) CalcError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => std.math.divTrunc(i64, a, b),
        // Remainder of truncating division; always representable, including
        // minInt % -1, which would trap if computed directly.
        .rem => if (b == 0) error.DivisionByZero else if (b == -1) 0 else @rem(a, b),
        .neg, .lparen => unreachable,
    };
}

/// Iterative operator-precedence (shunting-yard) evaluator, so deeply nested
/// input cannot exhaust the call stack. Its stacks are reused across lines.
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
        if (op == .neg) {
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try std.math.negate(top.*);
        } else {
            const b = self.values.pop().?;
            const top = &self.values.items[self.values.items.len - 1];
            top.* = try applyBinary(op, top.*, b);
        }
    }

    /// Evaluate one expression line.
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
                        try self.values.append(self.gpa, try parseLiteral(line[start..i]));
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.Syntax,
                }
            } else if (Op.binary(c)) |op| {
                // Left-associative: reduce everything binding at least as
                // tightly before pushing this operator.
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen or top.precedence() < op.precedence()) break;
                    try self.reduceTop();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else if (c == ')') {
                while (true) {
                    const top = self.ops.getLastOrNull() orelse return error.Syntax;
                    if (top == .lparen) break;
                    try self.reduceTop();
                }
                _ = self.ops.pop();
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduceTop();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }
};

/// Write the output line for each non-blank input line.
pub fn process(gpa: Allocator, input: []const u8, out: *Io.Writer) (Allocator.Error || Io.Writer.Error)!void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOfNone(u8, line, " \t") == null) continue;
        if (evaluator.evaluate(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Syntax, error.Overflow, error.DivisionByZero => try out.writeAll("error\n"),
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    try process(gpa, input, &stdout_writer.interface);
    try stdout_writer.interface.flush();
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try process(std.testing.allocator, input, &out.writer);
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
        "(-9223372036854775807 - 1) % -1\n(-9223372036854775807 - 1) / -1\n-9223372036854775808\n" ++
            "-(-9223372036854775807 - 1)\n9223372036854775807\n3037000499 * 3037000499\n",
        "0\nerror\nerror\nerror\n9223372036854775807\n9223372030926249001\n",
    );
}

test "syntax and blanks" {
    try expectOutput("1 +\nabc\n()\n1 2\n+1\n\n \t \n1\r\n((2))\n)(\n", "error\nerror\nerror\nerror\nerror\nerror\n2\nerror\n");
}

test "no trailing newline" {
    try expectOutput("--5\n2 * -3", "5\n-6\n");
}
