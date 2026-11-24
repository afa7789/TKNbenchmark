// calc: a 64-bit signed integer expression evaluator.
//
// Reads expressions from standard input, one per line, and prints each
// result (or `error`) on its own line. See SPEC.md for the grammar.
package calc

import "base:intrinsics"
import "core:bufio"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

main :: proc() {
	input := read_all(os.stdin)
	defer delete(input)

	writer: bufio.Writer
	bufio.writer_init(&writer, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&writer)
	w := bufio.writer_to_writer(&writer)

	ev: Evaluator
	evaluator_init(&ev)
	defer evaluator_destroy(&ev)

	rest := string(input)
	for len(rest) > 0 {
		line := rest
		if nl := strings.index_byte(rest, '\n'); nl >= 0 {
			line = rest[:nl]
			rest = rest[nl + 1:]
		} else {
			rest = ""
		}

		if is_blank(line) {
			continue
		}

		if value, ok := evaluate(&ev, line); ok {
			buf: [32]byte
			io.write_string(w, strconv.write_int(buf[:], value, 10))
		} else {
			io.write_string(w, "error")
		}
		io.write_byte(w, '\n')
	}

	bufio.writer_flush(&writer)
}

// read_all reads `f` until end of file. Unlike os.read_entire_file, it does
// not rely on the reported file size, so it works for pipes and terminals,
// and it keeps reading across short reads.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> []byte {
	buf := make([dynamic]byte, 0, 64 * 1024, allocator)
	chunk: [64 * 1024]byte
	for {
		n, err := os.read(f, chunk[:])
		if n > 0 {
			append(&buf, ..chunk[:n])
		}
		if err != nil || n <= 0 {
			break
		}
	}
	return buf[:]
}

is_blank :: proc(s: string) -> bool {
	for c in transmute([]byte)s {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Operators held on the operator stack.
Op :: enum u8 {
	LParen,
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
}

precedence :: proc(op: Op) -> int {
	switch op {
	case .LParen:             return 0
	case .Add, .Sub:          return 1
	case .Mul, .Div, .Mod:    return 2
	case .Neg:                return 3
	}
	unreachable()
}

// Evaluator is an iterative operator-precedence (shunting-yard) evaluator.
// It uses explicit stacks rather than recursion so that arbitrarily deep
// nesting cannot overflow the call stack. The stacks are reused across lines.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_init :: proc(ev: ^Evaluator, allocator := context.allocator) {
	ev.values = make([dynamic]i64, 0, 64, allocator)
	ev.ops = make([dynamic]Op, 0, 64, allocator)
}

evaluator_destroy :: proc(ev: ^Evaluator) {
	delete(ev.values)
	delete(ev.ops)
}

// evaluate parses and evaluates one expression. It returns ok = false on any
// syntax error, division by zero, or 64-bit overflow.
evaluate :: proc(ev: ^Evaluator, line: string) -> (result: i64, ok: bool) {
	clear(&ev.values)
	clear(&ev.ops)

	expect_operand := true
	i := 0
	for i < len(line) {
		c := line[i]
		switch c {
		case ' ', '\t':
			i += 1
			continue
		}

		if expect_operand {
			switch c {
			case '0' ..= '9':
				start := i
				for i < len(line) && line[i] >= '0' && line[i] <= '9' {
					i += 1
				}
				append(&ev.values, parse_literal(line[start:i]) or_return)
				expect_operand = false
				continue
			case '-':
				append(&ev.ops, Op.Neg)
			case '(':
				append(&ev.ops, Op.LParen)
			case:
				return 0, false
			}
		} else {
			op: Op
			switch c {
			case '+': op = .Add
			case '-': op = .Sub
			case '*': op = .Mul
			case '/': op = .Div
			case '%': op = .Mod
			case ')':
				for {
					top := pop_safe(&ev.ops) or_return
					if top == .LParen {
						break
					}
					apply(ev, top) or_return
				}
				i += 1
				continue
			case:
				return 0, false
			}
			// All binary operators are left-associative: reduce anything on
			// the stack that binds at least as tightly.
			for len(ev.ops) > 0 && precedence(ev.ops[len(ev.ops) - 1]) >= precedence(op) {
				apply(ev, pop(&ev.ops)) or_return
			}
			append(&ev.ops, op)
			expect_operand = true
		}
		i += 1
	}

	if expect_operand {
		return 0, false
	}
	for len(ev.ops) > 0 {
		op := pop(&ev.ops)
		if op == .LParen {
			return 0, false
		}
		apply(ev, op) or_return
	}
	if len(ev.values) != 1 {
		return 0, false
	}
	return ev.values[0], true
}

// parse_literal converts a run of ASCII digits, rejecting values above max(i64).
parse_literal :: proc(digits: string) -> (value: i64, ok: bool) {
	for c in transmute([]byte)digits {
		overflow: bool
		value, overflow = intrinsics.overflow_mul(value, 10)
		if overflow {
			return 0, false
		}
		value, overflow = intrinsics.overflow_add(value, i64(c - '0'))
		if overflow {
			return 0, false
		}
	}
	return value, true
}

// apply pops the operands of `op` from the value stack and pushes the result.
apply :: proc(ev: ^Evaluator, op: Op) -> (ok: bool) {
	if op == .Neg {
		a := pop_safe(&ev.values) or_return
		if a == min(i64) {
			return false
		}
		append(&ev.values, -a)
		return true
	}

	b := pop_safe(&ev.values) or_return
	a := pop_safe(&ev.values) or_return
	r := binary(op, a, b) or_return
	append(&ev.values, r)
	return true
}

binary :: proc(op: Op, a, b: i64) -> (r: i64, ok: bool) {
	overflow: bool
	switch op {
	case .Add:
		r, overflow = intrinsics.overflow_add(a, b)
	case .Sub:
		r, overflow = intrinsics.overflow_sub(a, b)
	case .Mul:
		r, overflow = intrinsics.overflow_mul(a, b)
	case .Div:
		if b == 0 || (a == min(i64) && b == -1) {
			return 0, false
		}
		r = a / b
	case .Mod:
		if b == 0 {
			return 0, false
		}
		// min(i64) % -1 is mathematically 0; avoid the trapping instruction.
		r = 0 if b == -1 else a % b
	case .LParen, .Neg:
		unreachable()
	}
	return r, !overflow
}
