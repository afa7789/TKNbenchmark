package suite

import "base:intrinsics"
import "core:bufio"

// The calculator is an operator-precedence (shunting-yard) evaluator with explicit
// stacks, so deeply nested input cannot exhaust the call stack.

Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
	Paren, // an open parenthesis awaiting its match
}

@(rodata)
OP_PRECEDENCE := [Op]u8 {
	.Paren = 0,
	.Add   = 1,
	.Sub   = 1,
	.Mul   = 2,
	.Div   = 2,
	.Mod   = 2,
	.Neg   = 3,
}

Calc :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

calc_destroy :: proc(c: ^Calc) {
	delete(c.values)
	delete(c.ops)
}

// calc_run evaluates each non-blank line of input and prints its value or "error".
calc_run :: proc(input: string, out: ^bufio.Writer) {
	c: Calc
	defer calc_destroy(&c)

	rest := input
	for line in split_line(&rest) {
		if is_blank(line) {
			continue
		}
		if v, ok := calc_eval(&c, line); ok {
			write_int(out, v)
			bufio.writer_write_byte(out, '\n')
		} else {
			write_line(out, "error")
		}
	}
}

is_blank :: proc(s: string) -> bool {
	for b in transmute([]byte)s {
		if b != ' ' && b != '\t' {
			return false
		}
	}
	return true
}

// calc_eval evaluates one expression. ok is false on a syntax error, division by
// zero, or 64-bit overflow.
calc_eval :: proc(c: ^Calc, s: string) -> (result: i64, ok: bool) {
	clear(&c.values)
	clear(&c.ops)

	expect_operand := true
	i := 0
	for {
		for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
			i += 1
		}
		if i == len(s) {
			break
		}
		ch := s[i]

		if expect_operand {
			switch ch {
			case '-':
				append(&c.ops, Op.Neg)
				i += 1
			case '(':
				append(&c.ops, Op.Paren)
				i += 1
			case '0' ..= '9':
				v: i64
				for i < len(s) && s[i] >= '0' && s[i] <= '9' {
					overflow_mul, overflow_add: bool
					v, overflow_mul = intrinsics.overflow_mul(v, 10)
					v, overflow_add = intrinsics.overflow_add(v, i64(s[i] - '0'))
					if overflow_mul || overflow_add {
						return 0, false // literal exceeds max(i64)
					}
					i += 1
				}
				append(&c.values, v)
				expect_operand = false
			case:
				return 0, false
			}
			continue
		}

		op: Op
		switch ch {
		case '+': op = .Add
		case '-': op = .Sub
		case '*': op = .Mul
		case '/': op = .Div
		case '%': op = .Mod
		case ')':
			for {
				top := pop_safe(&c.ops) or_return
				if top == .Paren {
					break
				}
				apply(c, top) or_return
			}
			i += 1
			continue
		case:
			return 0, false
		}
		// All binary operators are left-associative: reduce everything that binds at
		// least as tightly before pushing.
		for len(c.ops) > 0 {
			top := c.ops[len(c.ops) - 1]
			if OP_PRECEDENCE[top] < OP_PRECEDENCE[op] {
				break
			}
			pop(&c.ops)
			apply(c, top) or_return
		}
		append(&c.ops, op)
		expect_operand = true
		i += 1
	}

	if expect_operand {
		return 0, false // empty input or a dangling operator
	}
	for len(c.ops) > 0 {
		top := pop(&c.ops)
		if top == .Paren {
			return 0, false // unclosed parenthesis
		}
		apply(c, top) or_return
	}
	if len(c.values) != 1 {
		return 0, false
	}
	return c.values[0], true
}

// apply pops the operands of op from the value stack and pushes its result.
@(private = "file")
apply :: proc(c: ^Calc, op: Op) -> bool {
	if op == .Neg {
		n := len(c.values)
		if n < 1 {
			return false
		}
		v := c.values[n - 1]
		if v == min(i64) {
			return false
		}
		c.values[n - 1] = -v
		return true
	}

	n := len(c.values)
	if n < 2 {
		return false
	}
	a, b := c.values[n - 2], c.values[n - 1]
	r: i64
	overflow: bool
	#partial switch op {
	case .Add:
		r, overflow = intrinsics.overflow_add(a, b)
	case .Sub:
		r, overflow = intrinsics.overflow_sub(a, b)
	case .Mul:
		r, overflow = intrinsics.overflow_mul(a, b)
	case .Div:
		if b == 0 || (a == min(i64) && b == -1) {
			return false
		}
		r = a / b
	case .Mod:
		if b == 0 {
			return false
		}
		r = 0 if b == -1 else a % b
	case:
		return false
	}
	if overflow {
		return false
	}
	resize(&c.values, n - 1)
	c.values[n - 2] = r
	return true
}
