//! 64-bit signed integer expression evaluator.
//!
//! Uses an iterative operator-precedence (shunting-yard) evaluator so that
//! deeply nested input cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EvalError = error{ Syntax, DivisionByZero, Overflow };

const Op = enum {
    lparen,
    neg,
    add,
    sub,
    mul,
    div,
    rem,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .neg => 3,
        };
    }
};

/// Operand and operator stacks, reused across lines to avoid reallocating.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(self: *Evaluator, gpa: Allocator) void {
        self.values.deinit(gpa);
        self.ops.deinit(gpa);
        self.* = undefined;
    }

    /// Evaluates one expression. Returns null when `line` holds only blanks.
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
                    '+', '-', '*', '/', '%' => {
                        const op: Op = switch (c) {
                            '+' => .add,
                            '-' => .sub,
                            '*' => .mul,
                            '/' => .div,
                            '%' => .rem,
                            else => unreachable,
                        };
                        // Left associativity: reduce everything that binds at least as tightly.
                        while (self.ops.getLastOrNull()) |top| {
                            if (top.precedence() < op.precedence()) break;
                            try self.reduce();
                        }
                        try self.ops.append(gpa, op);
                        expect_operand = true;
                    },
                    ')' => {
                        while (true) {
                            const top = self.ops.getLastOrNull() orelse return error.Syntax;
                            if (top == .lparen) break;
                            try self.reduce();
                        }
                        _ = self.ops.pop();
                    },
                    else => return error.Syntax,
                }
            }
            i += 1;
        }

        if (!seen_token) return null;
        if (expect_operand) return error.Syntax;
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax;
            try self.reduce();
        }
        std.debug.assert(self.values.items.len == 1);
        return self.values.items[0];
    }

    /// Pops the top operator and applies it to the operand stack.
    fn reduce(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        const values = &self.values;
        if (op == .neg) {
            const top = &values.items[values.items.len - 1];
            top.* = try negate(top.*);
            return;
        }
        const rhs = values.pop().?;
        const lhs = &values.items[values.items.len - 1];
        lhs.* = try apply(op, lhs.*, rhs);
    }
};

fn parseLiteral(digits: []const u8) EvalError!i64 {
    var value: i64 = 0;
    for (digits) |d| {
        value = try checked(@mulWithOverflow(value, 10));
        value = try checked(@addWithOverflow(value, @as(i64, d - '0')));
    }
    return value;
}

fn checked(result: struct { i64, u1 }) EvalError!i64 {
    if (result[1] != 0) return error.Overflow;
    return result[0];
}

fn negate(x: i64) EvalError!i64 {
    return checked(@subWithOverflow(@as(i64, 0), x));
}

fn apply(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => checked(@addWithOverflow(a, b)),
        .sub => checked(@subWithOverflow(a, b)),
        .mul => checked(@mulWithOverflow(a, b)),
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
        .lparen, .neg => unreachable,
    };
}

/// Evaluates each line of `input`, printing its value or `error`.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        const result = evaluator.eval(gpa, line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => {
                try out.writeAll("error\n");
                continue;
            },
        };
        if (result) |value| try out.print("{d}\n", .{value});
    }
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n", "7\n-3\nerror\nerror\n");
}

test "precedence and associativity" {
    try expectOutput("(1 + 2) * 3\n1 + 2 * 3 - 4 / 2 % 3\n2*(3+4)*5\n10 - 4 - 3\n", "9\n5\n70\n3\n");
    try expectOutput("100 / 10 / 5\n-2 * 3\n- 2 - - 3", "2\n-6\n1\n");
}

test "division and remainder" {
    try expectOutput("7 / 2\n-7 % 3\n7 % -3\n0 / 5\n1 / 0\n5 % 0\n", "3\n-1\n1\n0\nerror\nerror\n");
}

test "overflow boundaries" {
    try expectOutput(
        \\(-9223372036854775807 - 1) % -1
        \\(-9223372036854775807 - 1) / -1
        \\-(-9223372036854775807 - 1)
        \\-9223372036854775807 - 1
        \\9223372036854775808
        \\-9223372036854775808
        \\3037000500 * 3037000500
        \\00009223372036854775807
        \\
    , "0\nerror\nerror\n-9223372036854775808\nerror\nerror\nerror\n9223372036854775807\n");
}

test "syntax errors and blanks" {
    try expectOutput("1 +\nabc\n()\n1 2\n+1\n)\n(\n1)\n2 (3)\n", "error\nerror\nerror\nerror\nerror\nerror\nerror\nerror\nerror\n");
    try expectOutput("\n  42  \n\t\n1+1\n", "42\n2\n");
    try expectOutput("((((((((((1))))))))))\n--5\n", "1\n5\n");
}

test "deep nesting does not recurse" {
    const gpa = std.testing.allocator;
    const depth = 100_000;
    const line = try gpa.alloc(u8, depth * 2 + 1);
    defer gpa.free(line);
    @memset(line[0..depth], '(');
    line[depth] = '7';
    @memset(line[depth + 1 ..], ')');
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);
    try std.testing.expectEqual(@as(?i64, 7), try evaluator.eval(gpa, line));
}
