//! calc: 64-bit signed integer expression evaluator (see SPEC.md).
//!
//! Each input line is evaluated with an iterative operator-precedence parser,
//! so arbitrarily deep nesting cannot overflow the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Value = i64;

const Op = enum {
    neg,
    add,
    sub,
    mul,
    div,
    mod,
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

pub const EvalError = error{ Syntax, DivisionByZero, Overflow } || Allocator.Error;

fn applyBinary(op: Op, a: Value, b: Value) EvalError!Value {
    return switch (op) {
        .add => std.math.add(Value, a, b),
        .sub => std.math.sub(Value, a, b),
        .mul => std.math.mul(Value, a, b),
        .div => {
            if (b == 0) return error.DivisionByZero;
            if (a == std.math.minInt(Value) and b == -1) return error.Overflow;
            return @divTrunc(a, b);
        },
        .mod => {
            if (b == 0) return error.DivisionByZero;
            if (b == -1) return 0; // minInt % -1 would trap
            return @rem(a, b);
        },
        .neg, .lparen => unreachable,
    };
}

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn isBlankLine(line: []const u8) bool {
    for (line) |c| {
        if (!isBlank(c)) return false;
    }
    return true;
}

/// Reusable evaluator; its stacks keep their capacity across lines.
pub const Evaluator = struct {
    gpa: Allocator,
    values: std.ArrayList(Value) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn init(gpa: Allocator) Evaluator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Evaluator) void {
        self.values.deinit(self.gpa);
        self.ops.deinit(self.gpa);
        self.* = undefined;
    }

    /// Returns the value of `line`, or an error on any syntax or arithmetic failure.
    pub fn evaluate(self: *Evaluator, line: []const u8) EvalError!Value {
        self.values.clearRetainingCapacity();
        self.ops.clearRetainingCapacity();

        var expect_operand = true;
        var i: usize = 0;
        while (true) {
            while (i < line.len and isBlank(line[i])) i += 1;
            if (i == line.len) break;
            const c = line[i];

            if (expect_operand) {
                switch (c) {
                    '-' => {
                        try self.ops.append(self.gpa, .neg);
                        i += 1;
                    },
                    '(' => {
                        try self.ops.append(self.gpa, .lparen);
                        i += 1;
                    },
                    '0'...'9' => {
                        try self.values.append(self.gpa, try parseNumber(line, &i));
                        expect_operand = false;
                    },
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                try self.reduceUntilParen();
                if (self.ops.pop() == null) return error.Syntax; // unmatched ')'
                i += 1;
            } else if (Op.fromBinary(c)) |op| {
                const p = op.precedence();
                while (self.ops.getLastOrNull()) |top| {
                    if (top.precedence() < p) break;
                    try self.reduceOnce();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
                i += 1;
            } else {
                return error.Syntax;
            }
        }

        if (expect_operand) return error.Syntax; // missing operand
        try self.reduceUntilParen();
        if (self.ops.items.len != 0 or self.values.items.len != 1) return error.Syntax; // unmatched '('
        return self.values.items[0];
    }

    fn parseNumber(line: []const u8, i: *usize) EvalError!Value {
        var v: Value = 0;
        var overflow = false;
        while (i.* < line.len and std.ascii.isDigit(line[i.*])) : (i.* += 1) {
            if (overflow) continue;
            const d: Value = line[i.*] - '0';
            const next = @mulWithOverflow(v, 10);
            const sum = @addWithOverflow(next[0], d);
            if (next[1] != 0 or sum[1] != 0) overflow = true else v = sum[0];
        }
        if (overflow) return error.Overflow;
        return v;
    }

    /// Applies the top operator to the value stack.
    fn reduceOnce(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        const b = self.values.pop().?;
        const result = if (op == .neg)
            std.math.negate(b) catch return error.Overflow
        else
            try applyBinary(op, self.values.pop().?, b);
        // Capacity is guaranteed: at least one value was just popped.
        self.values.appendAssumeCapacity(result);
    }

    fn reduceUntilParen(self: *Evaluator) EvalError!void {
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) break;
            try self.reduceOnce();
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buf);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    const out = &stdout_writer.interface;

    var evaluator = Evaluator.init(gpa);
    defer evaluator.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (isBlankLine(line)) continue;
        if (evaluator.evaluate(line)) |v| {
            try out.print("{d}\n", .{v});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
    try out.flush();
}

fn expectValue(expected: Value, line: []const u8) !void {
    var e = Evaluator.init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectEqual(expected, try e.evaluate(line));
}

fn expectFailure(expected: EvalError, line: []const u8) !void {
    var e = Evaluator.init(std.testing.allocator);
    defer e.deinit();
    try std.testing.expectError(expected, e.evaluate(line));
}

test "precedence and associativity" {
    try expectValue(7, "1 + 2 * 3");
    try expectValue(9, "(1 + 2) * 3");
    try expectValue(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectValue(3, "10 - 4 - 3");
    try expectValue(70, "2*(3+4)*5");
}

test "division and remainder" {
    try expectValue(-3, "-7 / 2");
    try expectValue(-1, "-7 % 3");
    try expectValue(1, "7 % -3");
    try expectValue(0, "(-9223372036854775807 - 1) % -1");
    try expectFailure(error.DivisionByZero, "1 / 0");
    try expectFailure(error.DivisionByZero, "5 % 0");
}

test "unary minus" {
    try expectValue(5, "--5");
    try expectValue(-6, "2 * -3");
    try expectValue(-5, "-(2 + 3)");
    try expectValue(std.math.minInt(Value), "-9223372036854775807 - 1");
}

test "overflow" {
    try expectFailure(error.Overflow, "9223372036854775807 + 1");
    try expectFailure(error.Overflow, "9223372036854775808");
    try expectFailure(error.Overflow, "-9223372036854775808");
    try expectFailure(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectFailure(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectFailure(error.Overflow, "3037000500 * 3037000500");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1 + 2\r" }) |line| {
        try expectFailure(error.Syntax, line);
    }
}
