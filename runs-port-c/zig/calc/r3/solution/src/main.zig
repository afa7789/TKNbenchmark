//! calc — a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value or
//! "error". Parsing uses an explicit-stack operator-precedence algorithm, so
//! arbitrarily deep nesting cannot exhaust the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const min_i64 = std.math.minInt(i64);

pub const EvalError = error{
    Syntax,
    DivisionByZero,
    Overflow,
};

const Op = enum(u8) {
    lparen,
    add,
    sub,
    mul,
    div,
    mod,
    neg,

    fn precedence(op: Op) u8 {
        return switch (op) {
            .lparen => 0,
            .add, .sub => 1,
            .mul, .div, .mod => 2,
            .neg => 3,
        };
    }

    fn binary(c: u8) ?Op {
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

fn applyBinary(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => std.math.add(i64, a, b),
        .sub => std.math.sub(i64, a, b),
        .mul => std.math.mul(i64, a, b),
        .div => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            if (a == min_i64 and b == -1) break :blk error.Overflow;
            break :blk @divTrunc(a, b);
        },
        .mod => blk: {
            if (b == 0) break :blk error.DivisionByZero;
            // minInt % -1 would trap; mathematically the remainder is 0.
            if (b == -1) break :blk 0;
            break :blk @rem(a, b);
        },
        .lparen, .neg => unreachable,
    };
}

fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isBlankLine(line: []const u8) bool {
    for (line) |c| {
        if (!isBlank(c)) return false;
    }
    return true;
}

/// Working storage reused across lines. Each stack holds at most one entry
/// per input character, so capacity is reserved up front and pushes cannot fail.
pub const Evaluator = struct {
    values: std.ArrayList(i64) = .empty,
    ops: std.ArrayList(Op) = .empty,

    pub fn deinit(ev: *Evaluator, gpa: Allocator) void {
        ev.values.deinit(gpa);
        ev.ops.deinit(gpa);
        ev.* = undefined;
    }

    /// Evaluates a single expression line.
    pub fn evaluate(ev: *Evaluator, gpa: Allocator, line: []const u8) (Allocator.Error || EvalError)!i64 {
        ev.values.clearRetainingCapacity();
        ev.ops.clearRetainingCapacity();
        try ev.values.ensureTotalCapacity(gpa, line.len);
        try ev.ops.ensureTotalCapacity(gpa, line.len);

        var want_operand = true;
        var i: usize = 0;
        while (i < line.len) {
            const c = line[i];
            if (isBlank(c)) {
                i += 1;
                continue;
            }

            if (want_operand) {
                if (isDigit(c)) {
                    const start = i;
                    while (i < line.len and isDigit(line[i])) i += 1;
                    const value = std.fmt.parseInt(i64, line[start..i], 10) catch |err| switch (err) {
                        error.Overflow => return error.Overflow,
                        error.InvalidCharacter => unreachable, // digits only
                    };
                    ev.values.appendAssumeCapacity(value);
                    want_operand = false;
                    continue;
                }
                ev.ops.appendAssumeCapacity(switch (c) {
                    '-' => .neg,
                    '(' => .lparen,
                    else => return error.Syntax,
                });
                i += 1;
                continue;
            }

            i += 1;
            if (c == ')') {
                while (ev.topOp()) |top| {
                    if (top == .lparen) break;
                    try ev.applyTop();
                }
                if (ev.ops.pop() == null) return error.Syntax;
                continue;
            }

            const op = Op.binary(c) orelse return error.Syntax;
            // All binary operators are left-associative.
            while (ev.topOp()) |top| {
                if (top.precedence() < op.precedence()) break;
                try ev.applyTop();
            }
            ev.ops.appendAssumeCapacity(op);
            want_operand = true;
        }

        if (want_operand) return error.Syntax;
        while (ev.topOp()) |top| {
            if (top == .lparen) return error.Syntax;
            try ev.applyTop();
        }
        std.debug.assert(ev.values.items.len == 1);
        return ev.values.items[0];
    }

    fn topOp(ev: *const Evaluator) ?Op {
        return ev.ops.getLastOrNull();
    }

    /// Pops the top operator and applies it to the value stack.
    fn applyTop(ev: *Evaluator) EvalError!void {
        const op = ev.ops.pop().?;
        const values = &ev.values;
        if (op == .neg) {
            const top = &values.items[values.items.len - 1];
            top.* = try std.math.negate(top.*);
            return;
        }
        const b = values.pop().?;
        const a = &values.items[values.items.len - 1];
        a.* = try applyBinary(op, a.*, b);
    }
};

fn processLine(ev: *Evaluator, gpa: Allocator, out: *Io.Writer, line: []const u8) !void {
    if (isBlankLine(line)) return;
    if (ev.evaluate(gpa, line)) |value| {
        try out.print("{d}\n", .{value});
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const in = &stdin.interface;

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;

    var ev: Evaluator = .{};
    defer ev.deinit(gpa);

    // Lines longer than the read buffer are accumulated here.
    var long_line: Io.Writer.Allocating = .init(gpa);
    defer long_line.deinit();

    while (true) {
        const line = in.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                long_line.clearRetainingCapacity();
                _ = in.streamDelimiterEnding(&long_line.writer, '\n') catch |e| switch (e) {
                    error.WriteFailed => return error.OutOfMemory,
                    error.ReadFailed => return stdin.err.?,
                };
                // Consume the delimiter, if the stream did not end first.
                in.toss(@min(in.bufferedLen(), 1));
                try processLine(&ev, gpa, out, long_line.written());
                continue;
            },
            error.ReadFailed => return stdin.err.?,
        } orelse break;
        try processLine(&ev, gpa, out, line);
    }
    try out.flush();
}

fn expectEval(expected: EvalError!i64, line: []const u8) !void {
    var ev: Evaluator = .{};
    defer ev.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected, ev.evaluate(std.testing.allocator, line));
}

test "arithmetic and precedence" {
    try expectEval(7, "1 + 2 * 3");
    try expectEval(9, "(1 + 2) * 3");
    try expectEval(5, "1 + 2 * 3 - 4 / 2 % 3");
    try expectEval(3, "10 - 4 - 3");
    try expectEval(5, "--5");
    try expectEval(-5, "-(2 + 3)");
}

test "division semantics" {
    try expectEval(-3, "-7 / 2");
    try expectEval(-1, "-7 % 3");
    try expectEval(1, "7 % -3");
    try expectEval(0, "(-9223372036854775807 - 1) % -1");
    try expectEval(error.DivisionByZero, "1 / 0");
    try expectEval(error.DivisionByZero, "5 % 0");
}

test "overflow" {
    try expectEval(error.Overflow, "9223372036854775807 + 1");
    try expectEval(error.Overflow, "9223372036854775808");
    try expectEval(error.Overflow, "-(-9223372036854775807 - 1)");
    try expectEval(error.Overflow, "(-9223372036854775807 - 1) / -1");
    try expectEval(error.Overflow, "3037000500 * 3037000500");
    try expectEval(min_i64, "-9223372036854775807 - 1");
}

test "syntax errors" {
    try expectEval(error.Syntax, "1 +");
    try expectEval(error.Syntax, "abc");
    try expectEval(error.Syntax, "()");
    try expectEval(error.Syntax, "1 2");
    try expectEval(error.Syntax, "+1");
    try expectEval(error.Syntax, "(1 + 2");
    try expectEval(error.Syntax, "1 + 2)");
}
