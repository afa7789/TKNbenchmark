// calc: a 64-bit signed integer expression evaluator.
//
// Reads expressions from standard input, one per line, and prints each
// value (or `error`) on its own line. See SPEC.md for the grammar.
//
// The parser is an iterative operator-precedence (shunting-yard) evaluator
// with explicit stacks, so deeply nested input cannot overflow the call stack.
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
	Neg,   // unary minus
	Paren, // open parenthesis marker
}

Eval_Error :: enum u8 {
	None,
	Syntax,
	Div_By_Zero,
	Overflow,
}

// Binding strength of binary operators; higher binds tighter.
precedence :: proc(op: Op) -> int {
	#partial switch op {
	case .Add, .Sub:       return 1
	case .Mul, .Div, .Mod: return 2
	case .Neg:             return 3
	}
	return 0
}

// Evaluator holds the scratch stacks, reused across lines to avoid reallocation.
Evaluator :: struct {
	values: [dynamic]i64,
	ops:    [dynamic]Op,
}

evaluator_destroy :: proc(e: ^Evaluator) {
	delete(e.values)
	delete(e.ops)
}

apply_binary :: proc(op: Op, a, b: i64) -> (i64, Eval_Error) {
	#partial switch op {
	case .Add:
		r, overflow := intrinsics.overflow_add(a, b)
		return r, .Overflow if overflow else .None
	case .Sub:
		r, overflow := intrinsics.overflow_sub(a, b)
		return r, .Overflow if overflow else .None
	case .Mul:
		r, overflow := intrinsics.overflow_mul(a, b)
		return r, .Overflow if overflow else .None
	case .Div:
		if b == 0 do return 0, .Div_By_Zero
		if a == min(i64) && b == -1 do return 0, .Overflow
		return a / b, .None
	case .Mod:
		if b == 0 do return 0, .Div_By_Zero
		if b == -1 do return 0, .None // avoids min(i64) % -1 trapping
		return a % b, .None
	}
	unreachable()
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
	r, err := apply_binary(op, a^, b)
	if err != .None do return err
	a^ = r
	return .None
}

// Evaluates one line. `blank` is true when the line holds only spaces/tabs.
evaluate :: proc(e: ^Evaluator, line: string) -> (value: i64, blank: bool, err: Eval_Error) {
	clear(&e.values)
	clear(&e.ops)

	expect_operand := true
	saw_token := false
	i := 0
	for i < len(line) {
		c := line[i]
		if c == ' ' || c == '\t' {
			i += 1
			continue
		}
		saw_token = true

		if expect_operand {
			switch c {
			case '0' ..= '9':
				n: i64 = 0
				for i < len(line) && line[i] >= '0' && line[i] <= '9' {
					m, o1 := intrinsics.overflow_mul(n, 10)
					s, o2 := intrinsics.overflow_add(m, i64(line[i] - '0'))
					if o1 || o2 do return 0, false, .Overflow
					n = s
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
				return 0, false, .Syntax
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
				for len(e.ops) > 0 && e.ops[len(e.ops) - 1] != .Paren {
					reduce_top(e) or_return
				}
				if len(e.ops) == 0 do return 0, false, .Syntax
				pop(&e.ops)
				i += 1
				continue
			case:
				return 0, false, .Syntax
			}
			// Left associativity: reduce everything that binds at least as tightly.
			p := precedence(op)
			for len(e.ops) > 0 {
				top := e.ops[len(e.ops) - 1]
				if top == .Paren || precedence(top) < p do break
				reduce_top(e) or_return
			}
			append(&e.ops, op)
			expect_operand = true
		}
		i += 1
	}

	if !saw_token do return 0, true, .None
	if expect_operand do return 0, false, .Syntax

	for len(e.ops) > 0 {
		if e.ops[len(e.ops) - 1] == .Paren do return 0, false, .Syntax
		reduce_top(e) or_return
	}
	assert(len(e.values) == 1)
	return e.values[0], false, .None
}

// Reads standard input until EOF. `os.read_entire_file` trusts the reported
// file size, which for a pipe on macOS is only the bytes currently buffered,
// so it would silently truncate large piped input.
read_all_stdin :: proc(allocator := context.allocator) -> (data: [dynamic]byte, ok: bool) {
	data = make([dynamic]byte, 0, 64 * 1024, allocator)
	chunk: [64 * 1024]byte
	for {
		n, err := os.read(os.stdin, chunk[:])
		append(&data, ..chunk[:n])
		switch err {
		case nil:
			if n == 0 do return data, true
		case .EOF, .Broken_Pipe:
			return data, true
		case:
			return data, false
		}
	}
}

main :: proc() {
	input, read_ok := read_all_stdin()
	defer delete(input)
	if !read_ok {
		os.exit(1)
	}

	w: bufio.Writer
	bufio.writer_init(&w, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&w)
	out := bufio.writer_to_writer(&w)

	e: Evaluator
	defer evaluator_destroy(&e)

	num_buf: [32]byte
	rest := string(input[:])
	for len(rest) > 0 {
		line := rest
		if idx := strings.index_byte(rest, '\n'); idx >= 0 {
			line = rest[:idx]
			rest = rest[idx + 1:]
		} else {
			rest = ""
		}

		value, blank, err := evaluate(&e, line)
		if blank do continue
		if err != .None {
			io.write_string(out, "error\n")
		} else {
			io.write_string(out, strconv.write_int(num_buf[:], value, 10))
			io.write_byte(out, '\n')
		}
	}
	bufio.writer_flush(&w)
}
