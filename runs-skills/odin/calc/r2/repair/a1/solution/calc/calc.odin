// Package calc evaluates signed 64-bit integer expressions.
//
// The grammar is:
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Parsing uses an explicit operator stack (shunting-yard), so arbitrarily
// deep nesting cannot exhaust the call stack.
package calc

import "base:intrinsics"

Error :: enum {
	None,
	Syntax,
	Division_By_Zero,
	Overflow,
}

@(private)
Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Neg,
	Paren, // open-parenthesis marker; never applied
}

@(private)
precedence :: proc(op: Op) -> int {
	switch op {
	case .Add, .Sub:
		return 1
	case .Mul, .Div, .Rem:
		return 2
	case .Neg:
		return 3
	case .Paren:
		return 0
	}
	return 0
}

// Evaluator holds scratch stacks reused across calls to avoid per-line allocation.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_init :: proc(e: ^Evaluator, allocator := context.allocator) {
	e.values = make([dynamic]i64, 0, 64, allocator)
	e.ops = make([dynamic]Op, 0, 64, allocator)
}

evaluator_destroy :: proc(e: ^Evaluator) {
	delete(e.values)
	delete(e.ops)
}

@(private)
is_space :: #force_inline proc(c: byte) -> bool {
	return c == ' ' || c == '\t'
}

@(private)
is_digit :: #force_inline proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}

// is_blank reports whether s is empty or holds only spaces and tabs.
is_blank :: proc(s: string) -> bool {
	for i in 0 ..< len(s) {
		if !is_space(s[i]) {
			return false
		}
	}
	return true
}

// evaluate parses and evaluates a single expression.
evaluate :: proc(e: ^Evaluator, src: string) -> (result: i64, err: Error) {
	clear(&e.values)
	clear(&e.ops)

	expect_operand := true
	i := 0
	for i < len(src) {
		c := src[i]
		if is_space(c) {
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
				n, i = parse_number(src, i) or_return
				append(&e.values, n)
				expect_operand = false
			case:
				return 0, .Syntax
			}
			continue
		}

		op: Op
		switch c {
		case '+':
			op = .Add
		case '-':
			op = .Sub
		case '*':
			op = .Mul
		case '/':
			op = .Div
		case '%':
			op = .Rem
		case ')':
			for {
				top, ok := pop_safe(&e.ops)
				if !ok {
					return 0, .Syntax
				}
				if top == .Paren {
					break
				}
				apply(e, top) or_return
			}
			i += 1
			continue
		case:
			return 0, .Syntax
		}

		// All binary operators are left-associative: reduce anything of
		// equal or higher precedence before pushing.
		p := precedence(op)
		for len(e.ops) > 0 {
			top := e.ops[len(e.ops) - 1]
			if top == .Paren || precedence(top) < p {
				break
			}
			pop(&e.ops)
			apply(e, top) or_return
		}
		append(&e.ops, op)
		expect_operand = true
		i += 1
	}

	if expect_operand {
		return 0, .Syntax
	}
	for len(e.ops) > 0 {
		top := pop(&e.ops)
		if top == .Paren {
			return 0, .Syntax
		}
		apply(e, top) or_return
	}
	if len(e.values) != 1 {
		return 0, .Syntax
	}
	return e.values[0], .None
}

// parse_number reads a run of decimal digits starting at start.
@(private)
parse_number :: proc(src: string, start: int) -> (value: i64, next: int, err: Error) {
	i := start
	overflow := false
	for i < len(src) && is_digit(src[i]) {
		if !overflow {
			d := i64(src[i] - '0')
			m, o1 := intrinsics.overflow_mul(value, 10)
			s, o2 := intrinsics.overflow_add(m, d)
			overflow = o1 || o2
			value = s
		}
		i += 1
	}
	if overflow {
		return 0, i, .Overflow
	}
	return value, i, .None
}

@(private)
apply :: proc(e: ^Evaluator, op: Op) -> Error {
	if op == .Neg {
		if len(e.values) < 1 {
			return .Syntax
		}
		v := &e.values[len(e.values) - 1]
		if v^ == min(i64) {
			return .Overflow
		}
		v^ = -v^
		return .None
	}

	if len(e.values) < 2 {
		return .Syntax
	}
	b := pop(&e.values)
	a := &e.values[len(e.values) - 1]
	r, err := binary(op, a^, b)
	if err != .None {
		return err
	}
	a^ = r
	return .None
}

// binary computes a op b with exact overflow and division checks.
binary :: proc(op: Op, a, b: i64) -> (r: i64, err: Error) {
	overflow: bool
	switch op {
	case .Add:
		r, overflow = intrinsics.overflow_add(a, b)
	case .Sub:
		r, overflow = intrinsics.overflow_sub(a, b)
	case .Mul:
		r, overflow = intrinsics.overflow_mul(a, b)
	case .Div:
		if b == 0 {
			return 0, .Division_By_Zero
		}
		if a == min(i64) && b == -1 {
			return 0, .Overflow
		}
		r = a / b
	case .Rem:
		if b == 0 {
			return 0, .Division_By_Zero
		}
		if b == -1 {
			return 0, .None
		}
		r = a % b
	case .Neg, .Paren:
		return 0, .Syntax
	}
	if overflow {
		return 0, .Overflow
	}
	return r, .None
}
