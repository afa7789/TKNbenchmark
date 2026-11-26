// Package calc implements the calc subcommand: a 64-bit signed integer
// expression evaluator, one expression per input line.
package calc

import (
	"bufio"
	"errors"
	"io"
	"math"
	"strconv"
)

// Evaluation errors. Callers of Run only see "error" in the output; the
// distinct values exist for Eval's callers and for tests.
var (
	ErrSyntax    = errors.New("syntax error")
	ErrDivByZero = errors.New("division by zero")
	ErrOverflow  = errors.New("integer overflow")
)

// Run executes the calc subcommand, reading from r and writing to w.
//
// Each input line is evaluated independently. Its value, or "error", is
// written on its own line; blank lines (only spaces and tabs) produce no
// output.
func Run(r io.Reader, w io.Writer) error {
	br := bufio.NewReaderSize(r, 1<<16)
	var (
		ev   evaluator
		long []byte // accumulates lines longer than br's buffer
		out  []byte
	)
	for {
		chunk, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			long = append(long, chunk...)
			continue
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		line := chunk
		if len(long) > 0 {
			long = append(long, chunk...)
			line = long
		}
		if n := len(line); n > 0 && line[n-1] == '\n' {
			line = line[:n-1]
		}

		if !isBlank(line) {
			out = out[:0]
			if v, everr := ev.eval(line); everr == nil {
				out = strconv.AppendInt(out, v, 10)
				out = append(out, '\n')
			} else {
				out = append(out, "error\n"...)
			}
			if _, werr := w.Write(out); werr != nil {
				return werr
			}
		}

		if err != nil { // io.EOF
			return nil
		}
		long = long[:0]
	}
}

// Eval evaluates a single expression. It returns ErrSyntax for input that
// does not match the grammar (including blank input), ErrDivByZero for a
// division or remainder by zero, and ErrOverflow when a literal or an
// intermediate result does not fit in an int64.
func Eval(expr string) (int64, error) {
	var ev evaluator
	return ev.eval([]byte(expr))
}

// op is an entry on the operator stack.
type op byte

const (
	opParen op = '('
	opNeg   op = '~'
	opAdd   op = '+'
	opSub   op = '-'
	opMul   op = '*'
	opDiv   op = '/'
	opRem   op = '%'
)

// prec returns the binding strength of o; parentheses bind weakest so that
// they are never popped by an operator.
func (o op) prec() int {
	switch o {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opRem:
		return 2
	case opNeg:
		return 3
	default:
		return 0
	}
}

// evaluator is an operator-precedence (shunting-yard) evaluator. It uses
// explicit stacks rather than recursion so that deeply nested input cannot
// exhaust the goroutine stack. The stacks are reused across calls.
type evaluator struct {
	vals []int64
	ops  []op
}

func (e *evaluator) eval(s []byte) (int64, error) {
	e.vals = e.vals[:0]
	e.ops = e.ops[:0]

	expectOperand := true
	for i := 0; i < len(s); {
		c := s[i]
		if c == ' ' || c == '\t' {
			i++
			continue
		}

		if expectOperand {
			switch {
			case isDigit(c):
				v, n, err := parseNumber(s[i:])
				if err != nil {
					return 0, err
				}
				e.vals = append(e.vals, v)
				i += n
				expectOperand = false
				continue
			case c == '-':
				e.ops = append(e.ops, opNeg)
			case c == '(':
				e.ops = append(e.ops, opParen)
			default:
				return 0, ErrSyntax
			}
			i++
			continue
		}

		switch o := op(c); o {
		case opAdd, opSub, opMul, opDiv, opRem:
			// All binary operators are left-associative: reduce everything
			// on the stack that binds at least as tightly.
			if err := e.reduce(o.prec()); err != nil {
				return 0, err
			}
			e.ops = append(e.ops, o)
			expectOperand = true
		case ')':
			if err := e.reduce(1); err != nil {
				return 0, err
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax // unmatched ')'
			}
			e.ops = e.ops[:len(e.ops)-1] // pop '('
		default:
			return 0, ErrSyntax
		}
		i++
	}

	if expectOperand {
		return 0, ErrSyntax // missing operand
	}
	if err := e.reduce(1); err != nil {
		return 0, err
	}
	if len(e.ops) != 0 || len(e.vals) != 1 {
		return 0, ErrSyntax // unmatched '('
	}
	return e.vals[0], nil
}

// reduce applies operators from the top of the stack while they bind at
// least as tightly as minPrec. It stops at an opening parenthesis.
func (e *evaluator) reduce(minPrec int) error {
	for len(e.ops) > 0 {
		o := e.ops[len(e.ops)-1]
		if o.prec() < minPrec {
			return nil
		}
		e.ops = e.ops[:len(e.ops)-1]

		if o == opNeg {
			top := &e.vals[len(e.vals)-1]
			if *top == math.MinInt64 {
				return ErrOverflow
			}
			*top = -*top
			continue
		}

		n := len(e.vals)
		v, err := apply(o, e.vals[n-2], e.vals[n-1])
		if err != nil {
			return err
		}
		e.vals[n-2] = v
		e.vals = e.vals[:n-1]
	}
	return nil
}

// apply computes a o b, reporting overflow and division by zero.
func apply(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		c := a + b
		if (c > a) != (b > 0) {
			return 0, ErrOverflow
		}
		return c, nil
	case opSub:
		c := a - b
		if (c < a) != (b > 0) {
			return 0, ErrOverflow
		}
		return c, nil
	case opMul:
		if a == 0 || b == 0 {
			return 0, nil
		}
		c := a * b
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || c/b != a {
			return 0, ErrOverflow
		}
		return c, nil
	case opDiv:
		if b == 0 {
			return 0, ErrDivByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case opRem:
		if b == 0 {
			return 0, ErrDivByZero
		}
		if b == -1 {
			return 0, nil // avoids the MinInt64 % -1 trap; the result is always 0
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + strconv.Quote(string(o)))
}

// parseNumber parses the maximal run of decimal digits at the start of s,
// returning its value and length.
func parseNumber(s []byte) (int64, int, error) {
	var v int64
	n := 0
	for ; n < len(s) && isDigit(s[n]); n++ {
		d := int64(s[n] - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, n, ErrOverflow
		}
		v = v*10 + d
	}
	return v, n, nil
}

// isBlank reports whether s holds only spaces and tabs.
func isBlank(s []byte) bool {
	for _, c := range s {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }
