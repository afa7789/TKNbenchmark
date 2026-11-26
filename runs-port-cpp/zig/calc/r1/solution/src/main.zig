//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value or
//! "error". Parsing uses explicit operand/operator stacks (shunting-yard)
//! rather than recursion, so arbitrarily deep nesting cannot overflow the
//! call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Int = i64;

const Op = enum {
    add,
    sub,
    mul,
    div,
    mod,
    neg,
    lparen,

    fn precedence(op: Op) u2 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .mod => 2,
            .neg => 3,
        };
    }

    fn fromBinary(c: u8) ?Op {
        return switch (c) {
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            '%' => .mod,
            else => null,
        };
    }
};

/// Every way evaluating a line can fail; all of them print "error".
pub const EvalError = error{ Syntax, Overflow, DivisionByZero } || Allocator.Error;

fn applyBinary(op: Op, lhs: Int, rhs: Int) EvalError!Int {
    return switch (op) {
        .add => std.math.add(Int, lhs, rhs),
        .sub => std.math.sub(Int, lhs, rhs),
        .mul => std.math.mul(Int, lhs, rhs),
        .div => blk: {
            if (rhs == 0) break :blk error.DivisionByZero;
            if (lhs == std.math.minInt(Int) and rhs == -1) break :blk error.Overflow;
            break :blk @divTrunc(lhs, rhs);
        },
        .mod => blk: {
            if (rhs == 0) break :blk error.DivisionByZero;
            // minInt % -1 is mathematically 0 but traps in hardware.
            if (rhs == -1) break :blk 0;
            break :blk @rem(lhs, rhs);
        },
        .neg, .lparen => unreachable,
    };
}

pub const Evaluator = struct {
    values: std.ArrayList(Int) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Returns the value of `line`. Stack storage is reused across calls.
    pub fn evaluate(self: *Evaluator, gpa: Allocator, line: []const u8) EvalError!Int {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (true) {
            while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
            if (i == line.len) break;
            const c = line[i];

            if (expect_operand) {
                switch (c) {
                    '0'...'9' => {
                        var value: Int = 0;
                        while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {
                            value = try std.math.mul(Int, value, 10);
                            value = try std.math.add(Int, value, line[i] - '0');
                        }
                        try self.values.append(gpa, value);
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(gpa, .neg),
                    '(' => try self.ops.append(gpa, .lparen),
                    else => return error.Syntax,
                }
                i += 1;
                continue;
            }

            if (c == ')') {
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen) break;
                    try self.reduce();
                } else return error.Syntax;
                _ = self.ops.pop();
            } else if (Op.fromBinary(c)) |op| {
                // Left associativity: reduce operators of equal or higher precedence.
                while (self.ops.getLastOrNull()) |top| {
                    if (top.precedence() < op.precedence()) break;
                    try self.reduce();
                }
                try self.ops.append(gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduce();
        }
        return self.values.items[self.values.items.len - 1];
    }

    /// Applies the operator on top of the stack to its operand(s).
    fn reduce(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        const values = self.values.items;
        if (op == .neg) {
            const top = &values[values.len - 1];
            top.* = try std.math.negate(top.*);
            return;
        }
        const rhs = self.values.pop().?;
        const lhs = &self.values.items[self.values.items.len - 1];
        lhs.* = try applyBinary(op, lhs.*, rhs);
    }
};

fn isBlank(line: []const u8) bool {
    return std.mem.indexOfNone(u8, line, " \t") == null;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlank(line)) continue;
        if (evaluator.evaluate(gpa, line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.Overflow, error.DivisionByZero => try out.writeAll("error\n"),
        }
    }
    try out.flush();
}

fn testEval(line: []const u8) EvalError!Int {
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(std.testing.allocator);
    return evaluator.evaluate(std.testing.allocator, line);
}

test "arithmetic and precedence" {
    try std.testing.expectEqual(@as(Int, 7), try testEval("1 + 2 * 3"));
    try std.testing.expectEqual(@as(Int, 3), try testEval("10 - 4 - 3"));
    try std.testing.expectEqual(@as(Int, -3), try testEval("-7 / 2"));
    try std.testing.expectEqual(@as(Int, -1), try testEval("-7 % 3"));
    try std.testing.expectEqual(@as(Int, 1), try testEval("7 % -3"));
    try std.testing.expectEqual(@as(Int, 5), try testEval("--5"));
    try std.testing.expectEqual(@as(Int, 0), try testEval("(-9223372036854775807 - 1) % -1"));
    try std.testing.expectEqual(@as(Int, std.math.minInt(Int)), try testEval("-9223372036854775807 - 1"));
}

test "errors" {
    try std.testing.expectError(error.Syntax, testEval("(1 + 2"));
    try std.testing.expectError(error.Syntax, testEval("()"));
    try std.testing.expectError(error.Syntax, testEval("1 2"));
    try std.testing.expectError(error.Syntax, testEval("+1"));
    try std.testing.expectError(error.Syntax, testEval("1)"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775807 + 1"));
    try std.testing.expectError(error.Overflow, testEval("-9223372036854775808"));
    try std.testing.expectError(error.Overflow, testEval("(-9223372036854775807 - 1) / -1"));
    try std.testing.expectError(error.DivisionByZero, testEval("1 / 0"));
    try std.testing.expectError(error.DivisionByZero, testEval("5 % 0"));
}
