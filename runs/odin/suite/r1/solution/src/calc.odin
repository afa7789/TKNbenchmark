package suite

import "base:intrinsics"
import "core:bufio"
import "core:strings"

Calc_Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,    // unary minus
	Lparen, // stack marker only; never applied
}

// Binding power; higher binds tighter. All binary operators are left-associative.
op_precedence := [Calc_Op]u8 {
	.Add    = 1,
	.Sub    = 1,
	.Mul    = 2,
	.Div    = 2,
	.Mod    = 2,
	.Neg    = 3,
	.Lparen = 0,
}

Calc_Error :: enum u8 {
	None,
	Syntax,
	Div_By_Zero,
	Overflow,
}

// Reusable evaluation stacks, kept across lines to avoid per-line allocation.
Calc_State :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Calc_Op,
}

// Evaluates each line of `input` as an expression and prints its value or
// `error`. Blank lines (only spaces/tabs) print nothing.
calc :: proc(input: []byte, out: ^bufio.Writer) {
	state: Calc_State
	defer {
		delete(state.values)
		delete(state.ops)
	}

	text := string(input)
	for line in strings.split_lines_iterator(&text) {
		if is_blank(line) {
			continue
		}
		if value, err := calc_eval(&state, line); err == .None {
			write_int(out, value)
			bufio.writer_write_byte(out, '\n')
		} else {
			write_line(out, "error")
		}
	}
}

@(private = "file")
is_blank :: proc(s: string) -> bool {
	for c in transmute([]byte)s {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Evaluates one expression with an operator-precedence (shunting-yard) parser.
// Explicit stacks keep arbitrarily deep nesting off the call stack.
calc_eval :: proc(st: ^Calc_State, s: string) -> (result: i64, err: Calc_Error) {
	clear(&st.values)
	clear(&st.ops)

	expect_operand := true
	i := 0
	for i < len(s) {
		c := s[i]
		switch {
		case c == ' ' || c == '\t':
			i += 1
			continue
		case expect_operand:
			switch c {
			case '0' ..= '9':
				v: i64
				for i < len(s) && s[i] >= '0' && s[i] <= '9' {
					m, o1 := intrinsics.overflow_mul(v, 10)
					a, o2 := intrinsics.overflow_add(m, i64(s[i] - '0'))
					if o1 || o2 {
						return 0, .Overflow
					}
					v = a
					i += 1
				}
				append(&st.values, v)
				expect_operand = false
				continue
			case '-':
				append(&st.ops, Calc_Op.Neg)
			case '(':
				append(&st.ops, Calc_Op.Lparen)
			case:
				return 0, .Syntax
			}
		case:
			op: Calc_Op
			switch c {
			case '+': op = .Add
			case '-': op = .Sub
			case '*': op = .Mul
			case '/': op = .Div
			case '%': op = .Mod
			case ')':
				for {
					top, ok := pop_safe(&st.ops)
					if !ok {
						return 0, .Syntax
					}
					if top == .Lparen {
						break
					}
					apply(st, top) or_return
				}
				i += 1
				continue
			case:
				return 0, .Syntax
			}
			for len(st.ops) > 0 && op_precedence[st.ops[len(st.ops) - 1]] >= op_precedence[op] {
				apply(st, pop(&st.ops)) or_return
			}
			append(&st.ops, op)
			expect_operand = true
		}
		i += 1
	}

	if expect_operand {
		return 0, .Syntax
	}
	for len(st.ops) > 0 {
		top := pop(&st.ops)
		if top == .Lparen {
			return 0, .Syntax
		}
		apply(st, top) or_return
	}
	assert(len(st.values) == 1)
	return st.values[0], .None
}

// Pops the operands of `op` from the value stack and pushes the result.
// The parser guarantees enough operands are present.
@(private = "file")
apply :: proc(st: ^Calc_State, op: Calc_Op) -> Calc_Error {
	if op == .Neg {
		top := &st.values[len(st.values) - 1]
		if top^ == min(i64) {
			return .Overflow
		}
		top^ = -top^
		return .None
	}

	b := pop(&st.values)
	a := &st.values[len(st.values) - 1]
	r: i64
	overflow: bool
	#partial switch op {
	case .Add:
		r, overflow = intrinsics.overflow_add(a^, b)
	case .Sub:
		r, overflow = intrinsics.overflow_sub(a^, b)
	case .Mul:
		r, overflow = intrinsics.overflow_mul(a^, b)
	case .Div:
		if b == 0 {
			return .Div_By_Zero
		}
		if a^ == min(i64) && b == -1 {
			return .Overflow
		}
		r = a^ / b
	case .Mod:
		if b == 0 {
			return .Div_By_Zero
		}
		// The quotient overflows but the remainder is well defined: 0.
		r = 0 if b == -1 else a^ % b
	case:
		unreachable()
	}
	if overflow {
		return .Overflow
	}
	a^ = r
	return .None
}
