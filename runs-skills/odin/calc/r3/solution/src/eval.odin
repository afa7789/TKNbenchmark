package main

import "base:intrinsics"

// Operators held on the evaluator's operator stack.
Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
	Paren,
}

Eval_Error :: enum u8 {
	None,
	Syntax,
	Div_By_Zero,
	Overflow,
}

// Reusable stacks so evaluating many lines does not reallocate.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_destroy :: proc(e: ^Evaluator) {
	delete(e.values)
	delete(e.ops)
}

@(private = "file")
precedence :: proc(op: Op) -> int {
	switch op {
	case .Add, .Sub:      return 1
	case .Mul, .Div, .Mod: return 2
	case .Neg:            return 3
	case .Paren:          return 0
	}
	return 0
}

@(private = "file")
is_blank :: #force_inline proc(c: u8) -> bool {
	return c == ' ' || c == '\t'
}

// Applies the operator on top of the stack to the value stack.
@(private = "file")
reduce :: proc(e: ^Evaluator) -> Eval_Error {
	op := pop(&e.ops)
	if op == .Neg {
		n := len(e.values)
		v, overflow := intrinsics.overflow_sub(i64(0), e.values[n - 1])
		if overflow {
			return .Overflow
		}
		e.values[n - 1] = v
		return .None
	}

	rhs := pop(&e.values)
	lhs := &e.values[len(e.values) - 1]
	overflow: bool
	#partial switch op {
	case .Add:
		lhs^, overflow = intrinsics.overflow_add(lhs^, rhs)
	case .Sub:
		lhs^, overflow = intrinsics.overflow_sub(lhs^, rhs)
	case .Mul:
		lhs^, overflow = intrinsics.overflow_mul(lhs^, rhs)
	case .Div:
		if rhs == 0 {
			return .Div_By_Zero
		}
		if lhs^ == min(i64) && rhs == -1 {
			return .Overflow
		}
		lhs^ /= rhs
	case .Mod:
		if rhs == 0 {
			return .Div_By_Zero
		}
		// min(i64) % -1 is mathematically 0 but traps or is undefined in hardware.
		lhs^ = rhs == -1 ? 0 : lhs^ % rhs
	case:
		unreachable()
	}
	return .Overflow if overflow else .None
}

// Evaluates one expression line with an iterative operator-precedence parser,
// so arbitrarily deep nesting cannot overflow the call stack.
evaluate :: proc(e: ^Evaluator, line: string) -> (result: i64, err: Eval_Error) {
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
			switch c {
			case '0' ..= '9':
				n: i64
				for i < len(line) && line[i] >= '0' && line[i] <= '9' {
					overflow_mul, overflow_add: bool
					n, overflow_mul = intrinsics.overflow_mul(n, 10)
					n, overflow_add = intrinsics.overflow_add(n, i64(line[i] - '0'))
					if overflow_mul || overflow_add {
						return 0, .Overflow
					}
					i += 1
				}
				append(&e.values, n)
				expect_operand = false
				continue
			case '-':
				append(&e.ops, Op.Neg)
			case '(':
				append(&e.ops, Op.Paren)
			case:
				return 0, .Syntax
			}
			i += 1
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

		// All binary operators are left-associative.
		prec := precedence(op)
		for len(e.ops) > 0 && precedence(e.ops[len(e.ops) - 1]) >= prec {
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
