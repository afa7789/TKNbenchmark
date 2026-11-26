//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value or
//! `error`. Parsing uses an explicit-stack operator-precedence algorithm so
//! that deeply nested input cannot overflow the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Int = i64;

/// Any reason an expression fails to produce a value.
pub const EvalError = error{ Syntax, Overflow, DivisionByZero };

// ---------- checked arithmetic ----------

fn checkedAdd(a: Int, b: Int) EvalError!Int {
    const r = @addWithOverflow(a, b);
    return if (r[1] != 0) error.Overflow else r[0];
}

fn checkedSub(a: Int, b: Int) EvalError!Int {
    const r = @subWithOverflow(a, b);
    return if (r[1] != 0) error.Overflow else r[0];
}

fn checkedMul(a: Int, b: Int) EvalError!Int {
    const r = @mulWithOverflow(a, b);
    return if (r[1] != 0) error.Overflow else r[0];
}

fn checkedDiv(a: Int, b: Int) EvalError!Int {
    if (b == 0) return error.DivisionByZero;
    if (a == std.math.minInt(Int) and b == -1) return error.Overflow;
    return @divTrunc(a, b);
}

fn checkedRem(a: Int, b: Int) EvalError!Int {
    if (b == 0) return error.DivisionByZero;
    // The remainder by -1 is always 0; special-casing it avoids the minInt trap.
    if (b == -1) return 0;
    return @rem(a, b);
}

fn checkedNeg(a: Int) EvalError!Int {
    if (a == std.math.minInt(Int)) return error.Overflow;
    return -a;
}

// ---------- evaluator ----------

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
};

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
    values: std.ArrayList(Int) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn init(gpa: Allocator) Evaluator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Evaluator) void {
        self.values.deinit(self.gpa);
        self.ops.deinit(self.gpa);
        self.* = undefined;
    }

    /// Returns the value of `line`, or an error describing why it has none.
    pub fn evaluate(self: *Evaluator, line: []const u8) (EvalError || Allocator.Error)!Int {
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
                        var value: Int = 0;
                        while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {
                            value = try checkedMul(value, 10);
                            value = try checkedAdd(value, line[i] - '0');
                        }
                        try self.values.append(self.gpa, value);
                        expect_operand = false;
                        continue;
                    },
                    '-' => try self.ops.append(self.gpa, .neg),
                    '(' => try self.ops.append(self.gpa, .lparen),
                    else => return error.Syntax,
                }
            } else if (c == ')') {
                while (self.ops.getLastOrNull()) |top| {
                    if (top == .lparen) break;
                    try self.reduce();
                } else return error.Syntax; // unbalanced ')'
                _ = self.ops.pop();
            } else if (Op.binary(c)) |op| {
                // All binary operators are left-associative.
                while (self.ops.getLastOrNull()) |top| {
                    if (top.precedence() < op.precedence()) break;
                    try self.reduce();
                }
                try self.ops.append(self.gpa, op);
                expect_operand = true;
            } else {
                return error.Syntax;
            }
            i += 1;
        }

        if (expect_operand) return error.Syntax; // missing operand (or empty)
        while (self.ops.getLastOrNull()) |top| {
            if (top == .lparen) return error.Syntax; // unbalanced '('
            try self.reduce();
        }
        if (self.values.items.len != 1) return error.Syntax;
        return self.values.items[0];
    }

    /// Applies the operator on top of the stack to its operands.
    fn reduce(self: *Evaluator) EvalError!void {
        const op = self.ops.pop().?;
        const rhs = self.values.pop().?;
        const result = switch (op) {
            .neg => try checkedNeg(rhs),
            .lparen => unreachable,
            else => blk: {
                const lhs = self.values.pop().?;
                break :blk switch (op) {
                    .add => try checkedAdd(lhs, rhs),
                    .sub => try checkedSub(lhs, rhs),
                    .mul => try checkedMul(lhs, rhs),
                    .div => try checkedDiv(lhs, rhs),
                    .rem => try checkedRem(lhs, rhs),
                    .neg, .lparen => unreachable,
                };
            },
        };
        // Capacity is guaranteed: at least one value was just popped.
        self.values.appendAssumeCapacity(result);
    }
};

/// Evaluates every line of `input`, writing one result line per non-blank line.
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
            error.Syntax, error.Overflow, error.DivisionByZero => try out.writeAll("error\n"),
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

// ---------- tests ----------

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

test "64-bit boundaries" {
    try expectOutput(
        \\(-9223372036854775807 - 1) % -1
        \\(-9223372036854775807 - 1) / -1
        \\-9223372036854775808
        \\-(-9223372036854775807 - 1)
        \\9223372036854775808
        \\-9223372036854775807 - 1
        \\3037000499 * 3037000499
        \\3037000500 * 3037000500
        \\
    ,
        \\0
        \\error
        \\error
        \\error
        \\error
        \\-9223372036854775808
        \\9223372030926249001
        \\error
        \\
    );
}

test "syntax errors and blank lines" {
    try expectOutput("1 +\nabc\n()\n1 2\n+1\n\n  42  \n\t\n1+1\n)\n((1)))\n", "error\nerror\nerror\nerror\nerror\n42\n2\nerror\nerror\n");
}

test "unary minus" {
    try expectOutput("--5\n2 * -3\n1 - -2\n-(2 + 3)\n- 2 * 3\n", "5\n-6\n3\n-5\n-6\n");
}
