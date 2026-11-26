//! Streaming evaluator for signed 64-bit integer expressions.
//!
//! ```
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! Spaces and tabs are permitted between tokens. All arithmetic is
//! overflow-checked. Input is consumed one byte at a time with an explicit
//! operator/operand stack (operator precedence parsing), so neither line
//! length nor nesting depth is bounded by the call stack.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Evaluator = @This();

/// Reasons an expression fails to evaluate. All of them print as `error`.
pub const Failure = error{ Syntax, DivisionByZero, Overflow };

/// Outcome of a completed line.
pub const Result = union(enum) {
    /// The line was empty or held only blanks.
    blank,
    value: i64,
    failure: Failure,
};

const Op = enum {
    lparen,
    negate,
    add,
    sub,
    mul,
    div,
    rem,

    fn fromByte(byte: u8) ?Op {
        return switch (byte) {
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            '%' => .rem,
            else => null,
        };
    }

    /// Binding strength of a binary operator; `null` for non-binary entries.
    fn precedence(op: Op) ?u8 {
        return switch (op) {
            .add, .sub => 1,
            .mul, .div, .rem => 2,
            .lparen, .negate => null,
        };
    }
};

const State = union(enum) {
    /// Nothing but blanks has been seen on this line.
    empty,
    /// Expecting the start of a `unary`.
    operand,
    /// Inside a NUMBER literal; holds the value accumulated so far.
    number: i64,
    /// A complete operand is on the value stack; expecting an operator or `)`.
    operator,
    /// The line has already failed; remaining bytes are ignored.
    failed: Failure,
};

gpa: Allocator,
ops: std.ArrayList(Op) = .empty,
values: std.ArrayList(i64) = .empty,
state: State = .empty,

pub fn init(gpa: Allocator) Evaluator {
    return .{ .gpa = gpa };
}

pub fn deinit(self: *Evaluator) void {
    self.ops.deinit(self.gpa);
    self.values.deinit(self.gpa);
    self.* = undefined;
}

/// Consumes the next byte of the current line (the `\n` terminator excluded).
pub fn feed(self: *Evaluator, byte: u8) Allocator.Error!void {
    if (self.state == .failed) return;
    self.step(byte) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |failure| self.state = .{ .failed = failure },
    };
}

/// Consumes a run of bytes belonging to the current line.
pub fn feedSlice(self: *Evaluator, bytes: []const u8) Allocator.Error!void {
    for (bytes) |byte| {
        if (self.state == .failed) return;
        try self.feed(byte);
    }
}

/// Ends the current line, returning its outcome and resetting for the next.
pub fn finish(self: *Evaluator) Allocator.Error!Result {
    defer self.reset();
    const value = self.complete() catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.Blank => return .blank,
        else => |failure| return .{ .failure = failure },
    };
    return .{ .value = value };
}

fn reset(self: *Evaluator) void {
    self.ops.clearRetainingCapacity();
    self.values.clearRetainingCapacity();
    self.state = .empty;
}

fn complete(self: *Evaluator) (Failure || Allocator.Error || error{Blank})!i64 {
    switch (self.state) {
        .empty => return error.Blank,
        .failed => |failure| return failure,
        .operand => return error.Syntax,
        .number => |n| try self.endPrimary(n),
        .operator => {},
    }
    try self.reduce(0);
    if (self.ops.items.len != 0) return error.Syntax; // unmatched '('
    std.debug.assert(self.values.items.len == 1);
    return self.values.items[0];
}

fn step(self: *Evaluator, byte: u8) (Failure || Allocator.Error)!void {
    switch (self.state) {
        .failed => unreachable,
        .empty, .operand => switch (byte) {
            ' ', '\t' => {},
            '-' => try self.pushOp(.negate),
            '(' => try self.pushOp(.lparen),
            '0'...'9' => self.state = .{ .number = byte - '0' },
            else => return error.Syntax,
        },
        .number => |n| switch (byte) {
            '0'...'9' => {
                const scaled = std.math.mul(i64, n, 10) catch return error.Overflow;
                const value = std.math.add(i64, scaled, byte - '0') catch return error.Overflow;
                self.state = .{ .number = value };
            },
            else => {
                try self.endPrimary(n);
                try self.step(byte);
            },
        },
        .operator => switch (byte) {
            ' ', '\t' => {},
            ')' => try self.closeParen(),
            else => {
                const op = Op.fromByte(byte) orelse return error.Syntax;
                try self.reduce(op.precedence().?);
                try self.pushOp(op);
            },
        },
    }
}

fn pushOp(self: *Evaluator, op: Op) Allocator.Error!void {
    try self.ops.append(self.gpa, op);
    self.state = .operand;
}

/// Records a completed primary and applies any unary minus directly before it.
fn endPrimary(self: *Evaluator, value: i64) (Failure || Allocator.Error)!void {
    try self.values.append(self.gpa, value);
    try self.applyNegations();
    self.state = .operator;
}

fn applyNegations(self: *Evaluator) Failure!void {
    const top = &self.values.items[self.values.items.len - 1];
    while (self.ops.getLastOrNull() == .negate) {
        _ = self.ops.pop();
        top.* = std.math.negate(top.*) catch return error.Overflow;
    }
}

fn closeParen(self: *Evaluator) Failure!void {
    try self.reduce(0);
    const open = self.ops.pop() orelse return error.Syntax; // no matching '('
    std.debug.assert(open == .lparen);
    try self.applyNegations();
}

/// Applies stacked binary operators binding at least as tightly as
/// `min_precedence`, stopping at the innermost open parenthesis.
fn reduce(self: *Evaluator, min_precedence: u8) Failure!void {
    while (self.ops.getLastOrNull()) |op| {
        const prec = op.precedence() orelse break;
        if (prec < min_precedence) break;
        _ = self.ops.pop();
        const rhs = self.values.pop().?;
        const lhs = &self.values.items[self.values.items.len - 1];
        lhs.* = try apply(op, lhs.*, rhs);
    }
}

/// Applies a binary operator with exact 64-bit semantics.
fn apply(op: Op, lhs: i64, rhs: i64) Failure!i64 {
    return switch (op) {
        .add => std.math.add(i64, lhs, rhs),
        .sub => std.math.sub(i64, lhs, rhs),
        .mul => std.math.mul(i64, lhs, rhs),
        .div => {
            if (rhs == 0) return error.DivisionByZero;
            if (rhs == -1 and lhs == std.math.minInt(i64)) return error.Overflow;
            return @divTrunc(lhs, rhs);
        },
        .rem => {
            if (rhs == 0) return error.DivisionByZero;
            // minInt % -1 is mathematically 0; avoid the trapping instruction.
            if (rhs == -1) return 0;
            return @rem(lhs, rhs);
        },
        .lparen, .negate => unreachable,
    };
}

/// Evaluates a single line; convenience wrapper used by tests.
pub fn evaluateLine(self: *Evaluator, line: []const u8) Allocator.Error!Result {
    try self.feedSlice(line);
    return self.finish();
}

fn expectLine(expected: Result, line: []const u8) !void {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    try std.testing.expectEqual(expected, try evaluator.evaluateLine(line));
}

test "precedence and associativity" {
    try expectLine(.{ .value = 7 }, "1 + 2 * 3");
    try expectLine(.{ .value = 9 }, "(1 + 2) * 3");
    try expectLine(.{ .value = 5 }, "1 + 2 * 3 - 4 / 2 % 3");
    try expectLine(.{ .value = 70 }, "2*(3+4)*5");
    try expectLine(.{ .value = 3 }, "10 - 4 - 3");
    try expectLine(.{ .value = 2 }, "100 / 10 / 5");
    try expectLine(.{ .value = 42 }, "\t 42  ");
    try expectLine(.{ .value = 7 }, "007");
}

test "unary minus" {
    try expectLine(.{ .value = 5 }, "--5");
    try expectLine(.{ .value = -6 }, "2 * -3");
    try expectLine(.{ .value = 3 }, "1 - -2");
    try expectLine(.{ .value = -5 }, "-(2 + 3)");
    try expectLine(.{ .value = -6 }, "-2 * 3");
    try expectLine(.{ .value = 1 }, "- ( - ( 1 ) )");
}

test "division and remainder" {
    try expectLine(.{ .value = -3 }, "-7 / 2");
    try expectLine(.{ .value = -1 }, "-7 % 3");
    try expectLine(.{ .value = 1 }, "7 % -3");
    try expectLine(.{ .failure = error.DivisionByZero }, "1 / 0");
    try expectLine(.{ .failure = error.DivisionByZero }, "5 % 0");
    try expectLine(.{ .value = 0 }, "(-9223372036854775807 - 1) % -1");
}

test "overflow" {
    try expectLine(.{ .value = std.math.maxInt(i64) }, "9223372036854775807");
    try expectLine(.{ .failure = error.Overflow }, "9223372036854775808");
    try expectLine(.{ .failure = error.Overflow }, "-9223372036854775808");
    try expectLine(.{ .failure = error.Overflow }, "9223372036854775807 + 1");
    try expectLine(.{ .failure = error.Overflow }, "(-9223372036854775807 - 1) / -1");
    try expectLine(.{ .failure = error.Overflow }, "-(-9223372036854775807 - 1)");
    try expectLine(.{ .failure = error.Overflow }, "3037000500 * 3037000500");
    try expectLine(.{ .value = std.math.minInt(i64) }, "-9223372036854775807 - 1");
}

test "syntax errors" {
    for ([_][]const u8{ "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "-", "1\r", "1 - - ", "(" }) |line| {
        try expectLine(.{ .failure = error.Syntax }, line);
    }
}

test "blank lines" {
    try expectLine(.blank, "");
    try expectLine(.blank, " \t ");
}

test "deep nesting" {
    const depth = 100_000;
    const line = try std.testing.allocator.alloc(u8, 2 * depth + 1);
    defer std.testing.allocator.free(line);
    @memset(line[0..depth], '(');
    line[depth] = '1';
    @memset(line[depth + 1 ..], ')');
    try expectLine(.{ .value = 1 }, line);
}

test "evaluator is reusable across lines" {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    try std.testing.expectEqual(Result{ .failure = error.Syntax }, try evaluator.evaluateLine("(1 +"));
    try std.testing.expectEqual(Result{ .value = 2 }, try evaluator.evaluateLine("1 + 1"));
}
