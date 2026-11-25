// Package calc evaluates 64-bit signed integer expressions.
//
// Grammar:
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//
// Evaluation is iterative (operator-precedence with explicit stacks), so
// arbitrarily deep nesting cannot overflow the call stack.
package calc

import "base:intrinsics"

Error :: enum {
	None,
	Syntax,
	Division_By_Zero,
	Overflow,
}

Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
	Paren,
}

// Binding strength; higher binds tighter. Paren is a barrier and never reduces.
precedence :: proc "contextless" (op: Op) -> int {
	switch op {
	case .Add, .Sub:        return 1
	case .Mul, .Div, .Mod:  return 2
	case .Neg:              return 3
	case .Paren:            return 0
	}
	return 0
}

// Reusable scratch state; keeps allocations amortized across many lines.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_destroy :: proc(e: ^Evaluator) {
	delete(e.values)
	delete(e.ops)
}

@(private)
is_blank :: proc "contextless" (c: byte) -> bool {
	return c == ' ' || c == '\t'
}

@(private)
is_digit :: proc "contextless" (c: byte) -> bool {
	return c >= '0' && c <= '9'
}

// Pops the top operator and applies it to the value stack.
@(private)
reduce :: proc(e: ^Evaluator) -> Error {
	op := pop(&e.ops)
	if op == .Neg {
		a := e.values[len(e.values) - 1]
		if a == min(i64) {
			return .Overflow
		}
		e.values[len(e.values) - 1] = -a
		return .None
	}

	b := pop(&e.values)
	a := e.values[len(e.values) - 1]
	r: i64
	overflow := false
	#partial switch op {
	case .Add:
		r, overflow = intrinsics.overflow_add(a, b)
	case .Sub:
		r, overflow = intrinsics.overflow_sub(a, b)
	case .Mul:
		r, overflow = intrinsics.overflow_mul(a, b)
	case .Div:
		if b == 0 {
			return .Division_By_Zero
		}
		if a == min(i64) && b == -1 {
			return .Overflow
		}
		r = a / b
	case .Mod:
		if b == 0 {
			return .Division_By_Zero
		}
		// The quotient overflows, but the remainder is exactly 0.
		r = 0 if b == -1 else a % b
	case:
		unreachable()
	}
	if overflow {
		return .Overflow
	}
	e.values[len(e.values) - 1] = r
	return .None
}

// Evaluates one expression. Errors are reported in left-to-right evaluation
// order, but any error makes the whole line fail, so the kind is informational.
evaluate :: proc(e: ^Evaluator, line: string) -> (result: i64, err: Error) {
	clear(&e.values)
	clear(&e.ops)

	expect_operand := true
	i := 0
	for i < len(line) {
		c := line[i]
		if is_blank(c) {
			i += 1
			continue
		}

		if expect_operand {
			switch {
			case c == '-':
				append(&e.ops, Op.Neg)
				i += 1
			case c == '(':
				append(&e.ops, Op.Paren)
				i += 1
			case is_digit(c):
				n: i64
				for i < len(line) && is_digit(line[i]) {
					d := i64(line[i] - '0')
					ok1, ok2: bool
					n, ok1 = intrinsics.overflow_mul(n, 10)
					n, ok2 = intrinsics.overflow_add(n, d)
					if ok1 || ok2 {
						return 0, .Overflow
					}
					i += 1
				}
				append(&e.values, n)
				expect_operand = false
			case:
				return 0, .Syntax
			}
			continue
		}

		op: Op
		switch c {
		case '+': op = .Add
		case '-': op = .Sub
		case '*': op = .Mul
		case '/': op = .Div
		case '%': op = .Mod
		case ')':
			for len(e.ops) > 0 && e.ops[len(e.ops) - 1] != .Paren {
				reduce(e) or_return
			}
			if len(e.ops) == 0 {
				return 0, .Syntax
			}
			pop(&e.ops)
			i += 1
			continue
		case:
			return 0, .Syntax
		}

		// Left associativity: reduce everything binding at least as tightly.
		p := precedence(op)
		for len(e.ops) > 0 && precedence(e.ops[len(e.ops) - 1]) >= p {
			reduce(e) or_return
		}
		append(&e.ops, op)
		expect_operand = true
		i += 1
	}

	if expect_operand {
		return 0, .Syntax
	}
	for len(e.ops) > 0 {
		if e.ops[len(e.ops) - 1] == .Paren {
			return 0, .Syntax
		}
		reduce(e) or_return
	}
	return e.values[0], .None
}
