//! calc: evaluate one 64-bit signed integer expression per input line.
//!
//! Parsing uses an iterative operator-precedence (shunting-yard) evaluator
//! with explicit stacks, so arbitrarily deep nesting cannot exhaust the
//! call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Operators held on the operator stack.
const Op = enum {
    lparen,
    neg,
    add,
    sub,
    mul,
    div,
    mod,

    fn fromByte(c: u8) ?Op {
        return switch (c) {
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            '%' => .mod,
            else => null,
        };
    }

    /// Binding strength; '(' never reduces by precedence.
    fn precedence(op: Op) u8 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .mod => 2,
            .neg => 3,
        };
    }
};

pub const EvalError = error{ Syntax, Overflow, DivisionByZero };

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Apply a binary operator with checked 64-bit semantics.
fn applyBinary(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            if (a == std.math.minInt(i64) and b == -1) break :blk error.Overflow;
            break :blk @divTrunc(a, b);
        },
        .mod => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            // The true remainder is 0; avoid the trapping minInt % -1.
            if (b == -1) break :blk 0;
            break :blk @rem(a, b);
        },
        .lparen, .neg => unreachable,
    };
}

/// Reusable evaluation state; the stacks keep their capacity across lines.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Evaluate a single expression line (without its trailing newline).
    pub fn evaluate(self: *Evaluator, gpa: Allocator, line: []const u8) (EvalError || Allocator.Error)!i64 {
        // Every token occupies at least one byte, bounding both stacks.
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();
        try self.values.ensureTotalCapacity(gpa, line.len + 1);
        try self.ops.ensureTotalCapacity(gpa, line.len + 1);
        return self.run(line);
    }

    fn run(self: *Evaluator, line: []const u8) EvalError!i64 {
        var want_operand = true;
        var i: usize = 0;

        while (true) {
            while (i < line.len and isBlank(line[i])) i += 1;

            if (want_operand) {
                if (i == line.len) return error.Syntax;
                switch (line[i]) {
                    '-' => {
                        self.ops.appendAssumeCapacity(.neg);
                        i += 1;
                    },
                    '(' => {
                        self.ops.appendAssumeCapacity(.lparen);
                        i += 1;
                    },
                    '0'...'9' => {
                        const start = i;
                        while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
                        self.values.appendAssumeCapacity(try parseNumber(line[start..i]));
                        want_operand = false;
                    },
                    else => return error.Syntax,
                }
                continue;
            }

            if (i == line.len) break;

            const c = line[i];
            i += 1;
            if (c == ')') {
                try self.reduceWhile(0);
                // Unmatched ')' leaves no '(' to discard.
                if (self.ops.pop() == null) return error.Syntax;
            } else if (Op.fromByte(c)) |op| {
                try self.reduceWhile(op.precedence());
                self.ops.appendAssumeCapacity(op);
                want_operand = true;
            } else {
                return error.Syntax;
            }
        }

        try self.reduceWhile(0);
        if (self.ops.items.len != 0) return error.Syntax; // unmatched '('
        return self.values.items[0];
    }

    /// Reduce while the top operator binds at least as tightly as `prec`.
    fn reduceWhile(self: *Evaluator, prec: u8) EvalError!void {
        while (self.ops.getLastOrNull()) |op| {
            if (op == .lparen or op.precedence() < prec) break;
            _ = self.ops.pop();
            try self.apply(op);
        }
    }

    fn apply(self: *Evaluator, op: Op) EvalError!void {
        const top = &self.values.items[self.values.items.len - 1];
        if (op == .neg) {
            top.* = try std.math.negate(top.*);
            return;
        }
        const b = self.values.pop().?;
        const a = &self.values.items[self.values.items.len - 1];
        a.* = try applyBinary(op, a.*, b);
    }
};

/// Parse a run of decimal digits as a non-negative i64.
fn parseNumber(digits: []const u8) EvalError!i64 {
    var v: i64 = 0;
    for (digits) |d| {
        v = try std.math.mul(i64, v, 10);
        v = try std.math.add(i64, v, d - '0');
    }
    return v;
}

fn isBlankLine(line: []const u8) bool {
    for (line) |c| {
        if (!isBlank(c)) return false;
    }
    return true;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;

    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlankLine(line)) continue;
        if (evaluator.evaluate(gpa, line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.Overflow, error.DivisionByZero => try out.writeAll("error\n"),
        }
    }
    try out.flush();
}

fn testEval(line: []const u8) EvalError!i64 {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    return ev.evaluate(std.testing.allocator, line) catch |err| switch (err) {
        error.OutOfMemory => unreachable,
        else => |e| e,
    };
}

test "arithmetic and precedence" {
    try std.testing.expectEqual(@as(i64, 7), try testEval("1 + 2 * 3"));
    try std.testing.expectEqual(@as(i64, -3), try testEval("-7 / 2"));
    try std.testing.expectEqual(@as(i64, -1), try testEval("-7 % 3"));
    try std.testing.expectEqual(@as(i64, 1), try testEval("7 % -3"));
    try std.testing.expectEqual(@as(i64, 5), try testEval("--5"));
    try std.testing.expectEqual(@as(i64, 0), try testEval("(-9223372036854775807 - 1) % -1"));
    try std.testing.expectEqual(@as(i64, std.math.minInt(i64)), try testEval("-9223372036854775807 - 1"));
}

test "errors" {
    try std.testing.expectError(error.Syntax, testEval("(1 + 2"));
    try std.testing.expectError(error.Syntax, testEval("1 2"));
    try std.testing.expectError(error.Syntax, testEval("+1"));
    try std.testing.expectError(error.Syntax, testEval("()"));
    try std.testing.expectError(error.Syntax, testEval("1)"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775807 + 1"));
    try std.testing.expectError(error.Overflow, testEval("9223372036854775808"));
    try std.testing.expectError(error.Overflow, testEval("-(-9223372036854775807 - 1)"));
    try std.testing.expectError(error.Overflow, testEval("(-9223372036854775807 - 1) / -1"));
    try std.testing.expectError(error.DivisionByZero, testEval("1 % 0"));
}
