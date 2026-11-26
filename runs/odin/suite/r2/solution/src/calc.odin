package main

import "base:intrinsics"
import "core:io"
import "core:strings"

// Evaluation uses an explicit operator stack (shunting-yard) rather than
// recursive descent, so deeply nested input cannot overflow the call stack.

@(private = "file")
Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
	Paren,
}

@(private = "file")
precedence :: proc(op: Op) -> int {
	switch op {
	case .Add, .Sub:
		return 1
	case .Mul, .Div, .Mod:
		return 2
	case .Neg:
		return 3
	case .Paren:
		return 0
	}
	return 0
}

@(private = "file")
Calc_Error :: enum u8 {
	None,
	Syntax,
	Div_By_Zero,
	Overflow,
}

@(private = "file")
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

// Pops one operator and applies it to the value stack.
@(private = "file")
reduce :: proc(e: ^Evaluator) -> Calc_Error {
	op := pop(&e.ops)
	if op == .Neg {
		x := &e.values[len(e.values) - 1]
		if x^ == min(i64) {
			return .Overflow
		}
		x^ = -x^
		return .None
	}

	b := pop(&e.values)
	a := &e.values[len(e.values) - 1]
	overflow: bool
	#partial switch op {
	case .Add:
		a^, overflow = intrinsics.overflow_add(a^, b)
	case .Sub:
		a^, overflow = intrinsics.overflow_sub(a^, b)
	case .Mul:
		a^, overflow = intrinsics.overflow_mul(a^, b)
	case .Div:
		if b == 0 {
			return .Div_By_Zero
		}
		if a^ == min(i64) && b == -1 {
			return .Overflow
		}
		a^ /= b
	case .Mod:
		if b == 0 {
			return .Div_By_Zero
		}
		a^ = 0 if b == -1 else a^ % b
	}
	return .Overflow if overflow else .None
}

@(private = "file")
is_blank :: #force_inline proc(c: byte) -> bool {
	return c == ' ' || c == '\t'
}

// Evaluates one expression line.
@(private = "file")
evaluate :: proc(e: ^Evaluator, line: string) -> (result: i64, err: Calc_Error) {
	clear(&e.values)
	clear(&e.ops)

	expect_operand := true
	i, n := 0, len(line)
	for i < n {
		c := line[i]
		if is_blank(c) {
			i += 1
			continue
		}

		if expect_operand {
			switch c {
			case '0' ..= '9':
				v: i64
				for i < n && line[i] >= '0' && line[i] <= '9' {
					overflow_m, overflow_a: bool
					v, overflow_m = intrinsics.overflow_mul(v, 10)
					v, overflow_a = intrinsics.overflow_add(v, i64(line[i] - '0'))
					if overflow_m || overflow_a {
						return 0, .Overflow
					}
					i += 1
				}
				append(&e.values, v)
				expect_operand = false
				continue
			case '(':
				append(&e.ops, Op.Paren)
			case '-':
				append(&e.ops, Op.Neg)
			case:
				return 0, .Syntax
			}
			i += 1
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
			op = .Mod
		case ')':
			for {
				if len(e.ops) == 0 {
					return 0, .Syntax
				}
				if e.ops[len(e.ops) - 1] == .Paren {
					pop(&e.ops)
					break
				}
				reduce(e) or_return
			}
			i += 1
			continue
		case:
			return 0, .Syntax
		}

		// All binary operators are left-associative.
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

// Evaluates each input line as a 64-bit integer expression, printing its
// value or `error`. Blank lines print nothing.
calc :: proc(input: []byte, w: io.Writer) {
	e: Evaluator
	defer {
		delete(e.values)
		delete(e.ops)
	}

	text := string(input)
	for line in strings.split_lines_iterator(&text) {
		if len(strings.trim(line, " \t")) == 0 {
			continue
		}
		if value, err := evaluate(&e, line); err == .None {
			write_int(w, value)
			io.write_byte(w, '\n')
		} else {
			write_line(w, "error")
		}
	}
}
