// calc: a 64-bit signed integer expression evaluator.
//
// Reads one expression per line from standard input and prints its value or
// `error`. Parsing uses an explicit operator stack (precedence climbing without
// recursion), so arbitrarily deep nesting cannot overflow the call stack.
package calc

import "base:intrinsics"
import "core:bufio"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

Op :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Neg,
	LParen,
}

Eval_Error :: enum u8 {
	None,
	Syntax,
	Divide_By_Zero,
	Overflow,
}

// Reusable scratch stacks shared across lines to avoid per-line allocation.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_destroy :: proc(e: ^Evaluator) {
	delete(e.values)
	delete(e.ops)
}

precedence :: proc(op: Op) -> int {
	switch op {
	case .Add, .Sub:        return 1
	case .Mul, .Div, .Mod:  return 2
	case .Neg:              return 3
	case .LParen:           return 0
	}
	return 0
}

is_blank :: proc(c: u8) -> bool {
	return c == ' ' || c == '\t'
}

is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

apply_binary :: proc(op: Op, a, b: i64) -> (result: i64, err: Eval_Error) {
	overflow: bool
	switch op {
	case .Add:
		result, overflow = intrinsics.overflow_add(a, b)
	case .Sub:
		result, overflow = intrinsics.overflow_sub(a, b)
	case .Mul:
		result, overflow = intrinsics.overflow_mul(a, b)
	case .Div:
		if b == 0 do return 0, .Divide_By_Zero
		if a == min(i64) && b == -1 do return 0, .Overflow
		result = a / b
	case .Mod:
		if b == 0 do return 0, .Divide_By_Zero
		// The quotient overflows but the remainder is well defined: zero.
		if b == -1 do return 0, .None
		result = a % b
	case .Neg, .LParen:
		unreachable()
	}
	if overflow do return 0, .Overflow
	return result, .None
}

// Pops the top operator and applies it to the value stack.
reduce_top :: proc(e: ^Evaluator) -> Eval_Error {
	op := pop(&e.ops)
	if op == .Neg {
		v := &e.values[len(e.values) - 1]
		if v^ == min(i64) do return .Overflow
		v^ = -v^
		return .None
	}
	b := pop(&e.values)
	a := &e.values[len(e.values) - 1]
	a^ = apply_binary(op, a^, b) or_return
	return .None
}

// Reduces every stacked operator binding at least as tightly as `prec`.
reduce_while :: proc(e: ^Evaluator, prec: int) -> Eval_Error {
	for len(e.ops) > 0 {
		top := e.ops[len(e.ops) - 1]
		if top == .LParen || precedence(top) < prec do break
		reduce_top(e) or_return
	}
	return .None
}

evaluate :: proc(e: ^Evaluator, line: string) -> (value: i64, err: Eval_Error) {
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
				append(&e.ops, Op.LParen)
				i += 1
			case is_digit(c):
				start := i
				for i < len(line) && is_digit(line[i]) do i += 1
				n, ok := strconv.parse_i64_of_base(line[start:i], 10)
				if !ok do return 0, .Overflow
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
			reduce_while(e, 0) or_return
			if len(e.ops) == 0 do return 0, .Syntax
			pop(&e.ops) // the matching '('
			i += 1
			continue
		case:
			return 0, .Syntax
		}
		// Left associativity: reduce operators of equal or higher precedence.
		reduce_while(e, precedence(op)) or_return
		append(&e.ops, op)
		expect_operand = true
		i += 1
	}

	if expect_operand do return 0, .Syntax
	reduce_while(e, 0) or_return
	if len(e.ops) != 0 do return 0, .Syntax // unclosed '('
	assert(len(e.values) == 1)
	return e.values[0], .None
}

is_blank_line :: proc(line: string) -> bool {
	for i in 0 ..< len(line) {
		if !is_blank(line[i]) do return false
	}
	return true
}

// Reads `f` until end of file. Unlike `os.read_entire_file`, this does not
// trust the reported file size, which for pipes on some platforms (e.g. macOS)
// is only the number of bytes currently buffered rather than the full stream.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([]byte, 64 * 1024, allocator) or_return
	total := 0
	for {
		if total == len(buf) {
			grown, alloc_err := make([]byte, 2 * len(buf), allocator)
			if alloc_err != nil {
				delete(buf, allocator)
				return nil, alloc_err
			}
			copy(grown, buf)
			delete(buf, allocator)
			buf = grown
		}
		n, read_err := os.read(f, buf[total:])
		total += n
		if read_err == .EOF || read_err == .Broken_Pipe || (read_err == nil && n == 0) do break
		if read_err != nil {
			delete(buf, allocator)
			return nil, read_err
		}
	}
	return buf[:total], nil
}

main :: proc() {
	input, read_err := read_all(os.stdin)
	if read_err != nil {
		os.exit(1)
	}
	defer delete(input)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_stream(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&w)
	out := bufio.writer_to_stream(&w)

	e: Evaluator
	defer evaluator_destroy(&e)

	buf: [32]u8
	rest := string(input)
	for len(rest) > 0 {
		line: string
		if nl := strings.index_byte(rest, '\n'); nl >= 0 {
			line, rest = rest[:nl], rest[nl + 1:]
		} else {
			line, rest = rest, ""
		}
		if is_blank_line(line) do continue

		if value, err := evaluate(&e, line); err == .None {
			io.write_string(out, strconv.write_int(buf[:], value, 10))
		} else {
			io.write_string(out, "error")
		}
		io.write_byte(out, '\n')
	}
	bufio.writer_flush(&w)
}

