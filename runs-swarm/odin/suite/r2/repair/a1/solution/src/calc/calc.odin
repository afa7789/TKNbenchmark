// Package calc implements `app calc`, which evaluates 64-bit signed integer expressions, one per line of standard input.
// See the "calc" section of SPEC.md.
package calc

import "base:intrinsics"
import "core:bufio"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// run is the entry point of the `calc` subcommand.
run :: proc() {
	input, read_err := read_all(os.stdin)
	if read_err != nil {
		fmt.eprintln("app calc: reading standard input:", read_err)
		os.exit(1)
	}
	defer delete(input)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&w)

	ev: Evaluator
	defer evaluator_destroy(&ev)

	rest := string(input)
	for line in strings.split_iterator(&rest, "\n") {
		if is_blank(line) {
			continue
		}
		if value, ok := evaluate(&ev, line); ok {
			buf: [32]byte
			bufio.writer_write_string(&w, strconv.write_int(buf[:], value, 10))
		} else {
			bufio.writer_write_string(&w, "error")
		}
		bufio.writer_write_byte(&w, '\n')
	}

	if err := bufio.writer_flush(&w); err != nil {
		fmt.eprintln("app calc: writing standard output:", err)
		os.exit(1)
	}
}

// read_all reads `f` until end of file. Unlike `os.read_entire_file`, it never trusts the size
// reported by `fstat`, which for pipes is only the amount currently buffered.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([]byte, 1 << 20, allocator) or_return
	n := 0
	for {
		if n == len(buf) {
			grown := make([]byte, 2 * len(buf), allocator) or_return
			copy(grown, buf)
			delete(buf, allocator)
			buf = grown
		}
		read, rerr := os.read(f, buf[n:])
		n += read
		if rerr == .EOF || (rerr == nil && read == 0) {
			return buf[:n], nil
		}
		if rerr != nil {
			delete(buf, allocator)
			return nil, rerr
		}
	}
}

// Operator is a pending operator on the evaluator's operator stack.
Operator :: enum u8 {
	Left_Paren,
	Negate,
	Add,
	Sub,
	Mul,
	Div,
	Rem,
}

// Evaluator holds the operand and operator stacks of an operator-precedence
// evaluator. It is iterative rather than recursive so that arbitrarily deep
// nesting cannot overflow the call stack; the stacks are reused across lines.
Evaluator :: struct {
	values:    [dynamic]i64,
	operators: [dynamic]Operator,
}

evaluator_destroy :: proc(ev: ^Evaluator) {
	delete(ev.values)
	delete(ev.operators)
}

// precedence reports the binding strength of an operator; higher binds tighter.
// Left_Paren has the lowest so that reductions never cross it.
precedence :: proc(op: Operator) -> int {
	switch op {
	case .Left_Paren: return 0
	case .Add, .Sub:  return 1
	case .Mul, .Div, .Rem: return 2
	case .Negate:     return 3
	}
	unreachable()
}

// evaluate computes the value of the expression in `line`, returning ok = false
// on any syntax error, division by zero or 64-bit overflow.
evaluate :: proc(ev: ^Evaluator, line: string) -> (result: i64, ok: bool) {
	clear(&ev.values)
	clear(&ev.operators)

	// The grammar alternates between expecting an operand (a number, '(' or
	// unary '-') and expecting an operator (a binary operator or ')').
	expect_operand := true
	i := 0
	for i < len(line) {
		c := line[i]
		switch {
		case c == ' ' || c == '\t':
			i += 1

		case expect_operand:
			switch c {
			case '-':
				append(&ev.operators, Operator.Negate)
				i += 1
			case '(':
				append(&ev.operators, Operator.Left_Paren)
				i += 1
			case '0'..='9':
				value: i64
				for i < len(line) && '0' <= line[i] && line[i] <= '9' {
					digit := i64(line[i] - '0')
					value = checked_mul(value, 10) or_return
					value = checked_add(value, digit) or_return
					i += 1
				}
				append(&ev.values, value)
				expect_operand = false
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
				reduce(ev, 1) or_return
				if len(ev.operators) == 0 {
					return 0, false // unbalanced ')'
				}
				pop(&ev.operators) // the matching '('
				i += 1
				continue
			case:
				return 0, false
			}
			// Left associativity: apply pending operators of equal or higher precedence first.
			reduce(ev, precedence(op)) or_return
			append(&ev.operators, op)
			expect_operand = true
			i += 1
		}
	}

	if expect_operand {
		return 0, false // empty expression or missing operand
	}
	reduce(ev, 1) or_return
	if len(ev.operators) != 0 {
		return 0, false // unbalanced '('
	}
	assert(len(ev.values) == 1)
	return ev.values[0], true
}

// reduce applies operators from the top of the stack while their precedence is
// at least `min_precedence`.
reduce :: proc(ev: ^Evaluator, min_precedence: int) -> (ok: bool) {
	for len(ev.operators) > 0 {
		op := ev.operators[len(ev.operators) - 1]
		if precedence(op) < min_precedence {
			break
		}
		pop(&ev.operators)

		if op == .Negate {
			top := &ev.values[len(ev.values) - 1]
			top^ = checked_sub(0, top^) or_return
			continue
		}

		rhs := pop(&ev.values)
		lhs := &ev.values[len(ev.values) - 1]
		lhs^ = apply(op, lhs^, rhs) or_return
	}
	return true
}

// apply evaluates a binary operator with the overflow and division rules of SPEC.md.
apply :: proc(op: Operator, a, b: i64) -> (result: i64, ok: bool) {
	#partial switch op {
	case .Add: return checked_add(a, b)
	case .Sub: return checked_sub(a, b)
	case .Mul: return checked_mul(a, b)
	case .Div:
		if b == 0 || (a == min(i64) && b == -1) {
			return 0, false
		}
		return a / b, true
	case .Rem:
		if b == 0 {
			return 0, false
		}
		if b == -1 {
			return 0, true // the quotient may overflow, but the remainder is always 0
		}
		return a % b, true
	}
	unreachable()
}

checked_add :: #force_inline proc(a, b: i64) -> (i64, bool) {
	r, overflow := intrinsics.overflow_add(a, b)
	return r, !overflow
}

checked_sub :: #force_inline proc(a, b: i64) -> (i64, bool) {
	r, overflow := intrinsics.overflow_sub(a, b)
	return r, !overflow
}

checked_mul :: #force_inline proc(a, b: i64) -> (i64, bool) {
	r, overflow := intrinsics.overflow_mul(a, b)
	return r, !overflow
}

// is_blank reports whether a line holds only spaces and tabs.
is_blank :: proc(line: string) -> bool {
	for c in transmute([]byte)line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}
