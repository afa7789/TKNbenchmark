// Package calc evaluates one 64-bit signed integer expression per line of standard input.
// See the "calc" section of SPEC.md.
package calc

import "base:intrinsics"
import "core:bufio"
import "core:bytes"
import "core:fmt"
import "core:os"
import "core:strconv"

import "../input"

// run is the entry point for `app calc`. It reads standard input, writes standard output,
// and returns normally so that the process exits with status 0.
run :: proc() {
	data, read_err := input.read_all(os.stdin)
	if read_err != nil {
		fmt.eprintln("calc: failed to read standard input:", read_err)
		return
	}
	defer delete(data)

	out: bufio.Writer
	bufio.writer_init(&out, os.to_stream(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&out)
	defer bufio.writer_flush(&out)

	ev: Evaluator
	defer evaluator_destroy(&ev)

	rest := data
	for len(rest) > 0 {
		line: []byte
		if i := bytes.index_byte(rest, '\n'); i >= 0 {
			line, rest = rest[:i], rest[i + 1:]
		} else {
			line, rest = rest, nil
		}

		if is_blank(line) {
			continue
		}

		if value, ok := evaluate(&ev, line); ok {
			digits: [32]byte
			bufio.writer_write_string(&out, strconv.write_int(digits[:], value, 10))
		} else {
			bufio.writer_write_string(&out, "error")
		}
		bufio.writer_write_byte(&out, '\n')
	}
}

// Op is an operator held on the evaluator's operator stack.
Op :: enum u8 {
	Open_Paren,
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Neg,
}

// precedence orders operators for reduction; a higher value binds tighter.
// Open_Paren has the lowest so that reductions never cross it.
@(rodata)
precedence := [Op]u8 {
	.Open_Paren = 0,
	.Add        = 1,
	.Sub        = 1,
	.Mul        = 2,
	.Div        = 2,
	.Rem        = 2,
	.Neg        = 3,
}

// Evaluator holds the operand and operator stacks. They are reused across lines so that
// evaluating many expressions does not allocate per line. Parsing is iterative (operator
// precedence with explicit stacks), so arbitrarily deep nesting cannot overflow the call stack.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_destroy :: proc(ev: ^Evaluator) {
	delete(ev.values)
	delete(ev.ops)
}

// evaluate parses and evaluates one expression. It returns ok = false on any syntax error,
// division or remainder by zero, or 64-bit overflow.
evaluate :: proc(ev: ^Evaluator, line: []byte) -> (value: i64, ok: bool) {
	clear(&ev.values)
	clear(&ev.ops)

	// The parser alternates between expecting an operand (a number, '(' or unary '-')
	// and expecting an operator (a binary operator, ')' or the end of the line).
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
				append(&ev.ops, Op.Open_Paren)
				i += 1
			case '-':
				append(&ev.ops, Op.Neg)
				i += 1
			case:
				return 0, false
			}

		case c == ')':
			for {
				top := pop_safe(&ev.ops) or_return
				if top == .Open_Paren {
					break
				}
				apply(ev, top) or_return
			}
			i += 1

		case:
			op: Op
			switch c {
			case '+': op = .Add
			case '-': op = .Sub
			case '*': op = .Mul
			case '/': op = .Div
			case '%': op = .Rem
			case:     return 0, false
			}
			// All binary operators are left-associative: reduce equal precedence too.
			for len(ev.ops) > 0 && precedence[ev.ops[len(ev.ops) - 1]] >= precedence[op] {
				apply(ev, pop(&ev.ops)) or_return
			}
			append(&ev.ops, op)
			expect_operand = true
			i += 1
		}
	}

	if expect_operand {
		return 0, false
	}
	for len(ev.ops) > 0 {
		top := pop(&ev.ops)
		if top == .Open_Paren {
			return 0, false
		}
		apply(ev, top) or_return
	}
	assert(len(ev.values) == 1)
	return ev.values[0], true
}

// parse_number reads the run of decimal digits starting at line[start], failing if the
// literal exceeds the i64 range. It returns the value and the index just past the digits.
parse_number :: proc(line: []byte, start: int) -> (value: i64, end: int, ok: bool) {
	end = start
	for end < len(line) && line[end] >= '0' && line[end] <= '9' {
		overflow: bool
		if value, overflow = intrinsics.overflow_mul(value, 10); overflow {
			return
		}
		if value, overflow = intrinsics.overflow_add(value, i64(line[end] - '0')); overflow {
			return
		}
		end += 1
	}
	return value, end, true
}

// apply pops the operands of op from the value stack and pushes its result.
// The parser guarantees enough operands are present.
apply :: proc(ev: ^Evaluator, op: Op) -> (ok: bool) {
	if op == .Neg {
		top := &ev.values[len(ev.values) - 1]
		if top^ == min(i64) {
			return false
		}
		top^ = -top^
		return true
	}

	rhs := pop(&ev.values)
	lhs := &ev.values[len(ev.values) - 1]
	a, b := lhs^, rhs
	result: i64
	overflow: bool
	switch op {
	case .Add:
		result, overflow = intrinsics.overflow_add(a, b)
	case .Sub:
		result, overflow = intrinsics.overflow_sub(a, b)
	case .Mul:
		result, overflow = intrinsics.overflow_mul(a, b)
	case .Div:
		if b == 0 || (a == min(i64) && b == -1) {
			return false
		}
		result = a / b
	case .Rem:
		if b == 0 {
			return false
		}
		// min(i64) % -1 is mathematically 0 but traps on most hardware.
		result = 0 if b == -1 else a % b
	case .Open_Paren, .Neg:
		unreachable()
	}
	if overflow {
		return false
	}
	lhs^ = result
	return true
}

is_blank :: proc(line: []byte) -> bool {
	for c in line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}
