package calc

import "base:intrinsics"

// Iterative operator-precedence evaluator for the grammar in SPEC.md:
//
//     expr    := term    (('+' | '-') term)*
//     term    := unary   (('*' | '/' | '%') unary)*
//     unary   := '-' unary | primary
//     primary := NUMBER | '(' expr ')'
//
// Explicit operand/operator stacks are used instead of recursion so that
// arbitrarily deep nesting (`((((…))))`, `----…1`) cannot exhaust the call
// stack. The stacks are kept in the Evaluator and reused across lines.
@(private)
Evaluator :: struct {
	values:    [dynamic]i64,
	operators: [dynamic]Operator,
}

@(private)
evaluator_destroy :: proc(ev: ^Evaluator) {
	delete(ev.values)
	delete(ev.operators)
}

@(private = "file")
Operator :: enum u8 {
	Left_Paren, // marker on the operator stack, never applied
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Neg,
}

// Binding strength; higher binds tighter. Left_Paren is lowest so that it
// stops reductions triggered by binary operators.
@(private = "file", rodata)
PRECEDENCE := [Operator]u8 {
	.Left_Paren = 0,
	.Add        = 1,
	.Sub        = 1,
	.Mul        = 2,
	.Div        = 2,
	.Rem        = 2,
	.Neg        = 3,
}

// Evaluates one line. `ok` is false on any syntax error, division by zero
// or 64-bit overflow.
@(private)
evaluate :: proc(ev: ^Evaluator, line: string) -> (value: i64, ok: bool) {
	clear(&ev.values)
	clear(&ev.operators)

	// The parser alternates between expecting an operand (a number, `(` or
	// unary `-`) and expecting an operator (a binary operator or `)`).
	expect_operand := true
	i := 0
	for i < len(line) {
		c := line[i]
		switch {
		case c == ' ' || c == '\t':
			i += 1

		case expect_operand:
			switch c {
			case '0' ..= '9':
				n: i64
				n, i = parse_number(line, i) or_return
				append(&ev.values, n)
				expect_operand = false
			case '(':
				append(&ev.operators, Operator.Left_Paren)
				i += 1
			case '-':
				append(&ev.operators, Operator.Neg)
				i += 1
			case:
				return 0, false
			}

		case:
			op: Operator
			switch c {
			case '+': op = .Add
			case '-': op = .Sub
			case '*': op = .Mul
			case '/': op = .Div
			case '%': op = .Rem
			case ')':
				reduce(ev, PRECEDENCE[.Left_Paren] + 1) or_return
				if len(ev.operators) == 0 {
					return 0, false // unbalanced `)`
				}
				pop(&ev.operators) // the matching Left_Paren
				i += 1
				continue
			case:
				return 0, false
			}
			// All binary operators are left-associative: first apply every
			// pending operator that binds at least as tightly.
			reduce(ev, PRECEDENCE[op]) or_return
			append(&ev.operators, op)
			expect_operand = true
			i += 1
		}
	}

	if expect_operand {
		return 0, false // empty input or missing operand
	}
	reduce(ev, PRECEDENCE[.Left_Paren] + 1) or_return
	if len(ev.operators) != 0 {
		return 0, false // unbalanced `(`
	}
	assert(len(ev.values) == 1)
	return ev.values[0], true
}

// Parses the run of decimal digits starting at `start`; fails if the literal
// does not fit in an i64.
@(private = "file")
parse_number :: proc(line: string, start: int) -> (value: i64, end: int, ok: bool) {
	end = start
	for end < len(line) && line[end] >= '0' && line[end] <= '9' {
		digit := i64(line[end] - '0')
		overflow_mul, overflow_add: bool
		value, overflow_mul = intrinsics.overflow_mul(value, 10)
		value, overflow_add = intrinsics.overflow_add(value, digit)
		if overflow_mul || overflow_add {
			return 0, end, false
		}
		end += 1
	}
	return value, end, true
}

// Applies operators from the top of the stack while their precedence is at
// least `min_precedence`.
@(private = "file")
reduce :: proc(ev: ^Evaluator, min_precedence: u8) -> (ok: bool) {
	for len(ev.operators) > 0 {
		op := ev.operators[len(ev.operators) - 1]
		if PRECEDENCE[op] < min_precedence {
			break
		}
		pop(&ev.operators)

		if op == .Neg {
			top := &ev.values[len(ev.values) - 1]
			top^ = apply_neg(top^) or_return
			continue
		}

		rhs := pop(&ev.values)
		lhs := &ev.values[len(ev.values) - 1]
		lhs^ = apply_binary(op, lhs^, rhs) or_return
	}
	return true
}

@(private = "file")
apply_neg :: proc(x: i64) -> (result: i64, ok: bool) {
	if x == min(i64) {
		return 0, false
	}
	return -x, true
}

@(private = "file")
apply_binary :: proc(op: Operator, lhs, rhs: i64) -> (result: i64, ok: bool) {
	overflow: bool
	#partial switch op {
	case .Add:
		result, overflow = intrinsics.overflow_add(lhs, rhs)
	case .Sub:
		result, overflow = intrinsics.overflow_sub(lhs, rhs)
	case .Mul:
		result, overflow = intrinsics.overflow_mul(lhs, rhs)
	case .Div:
		if rhs == 0 || (lhs == min(i64) && rhs == -1) {
			return 0, false
		}
		result = lhs / rhs
	case .Rem:
		if rhs == 0 {
			return 0, false
		}
		// min(i64) % -1 is mathematically 0 but traps on most hardware.
		result = rhs == -1 ? 0 : lhs % rhs
	case:
		unreachable()
	}
	return result, !overflow
}
