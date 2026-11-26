package calc

import (
	"bufio"
	"errors"
	"io"
	"math"
	"strconv"
)

var (
	errSyntax   = errors.New("syntax error")
	errDivZero  = errors.New("division by zero")
	errOverflow = errors.New("integer overflow")
)

// Operator codes held on the operator stack. opNeg is unary minus; opParen
// marks an open parenthesis.
const (
	opParen byte = '('
	opNeg   byte = 'n'
	opAdd   byte = '+'
	opSub   byte = '-'
	opMul   byte = '*'
	opDiv   byte = '/'
	opRem   byte = '%'
)

// Run executes the calc subcommand: each line of r is evaluated and its value,
// or "error", is written to w. Blank lines produce no output.
func Run(r io.Reader, w io.Writer) error {
	br := bufio.NewReaderSize(r, 64<<10)
	var (
		ev   evaluator
		line []byte // accumulates lines longer than the reader's buffer
		out  []byte
	)
	for {
		chunk, err := br.ReadSlice('\n')
		if err == bufio.ErrBufferFull {
			line = append(line, chunk...)
			continue
		}
		if err != nil && err != io.EOF {
			return err
		}
		if len(line) > 0 {
			line = append(line, chunk...)
			chunk = line
		}
		if n := len(chunk); n > 0 && chunk[n-1] == '\n' {
			chunk = chunk[:n-1]
		}
		if !isBlank(chunk) {
			out = out[:0]
			if v, everr := ev.eval(chunk); everr != nil {
				out = append(out, "error"...)
			} else {
				out = strconv.AppendInt(out, v, 10)
			}
			out = append(out, '\n')
			if _, werr := w.Write(out); werr != nil {
				return werr
			}
		}
		if cap(line) > 1<<20 {
			line = nil // don't pin a huge buffer after one very long line
		} else {
			line = line[:0]
		}
		if err == io.EOF {
			return nil
		}
	}
}

// Eval evaluates a single expression according to the grammar in SPEC.md.
func Eval(expr []byte) (int64, error) {
	var ev evaluator
	return ev.eval(expr)
}

func isBlank(b []byte) bool {
	for _, c := range b {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// evaluator is an operator-precedence (shunting-yard) evaluator. It uses
// explicit stacks rather than recursion so that arbitrarily deep nesting
// cannot exhaust the goroutine stack. Its stacks are reused across calls.
type evaluator struct {
	ops  []byte
	vals []int64
}

func (e *evaluator) eval(s []byte) (int64, error) {
	e.ops = e.ops[:0]
	e.vals = e.vals[:0]
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
				return 0, errSyntax
			}
			i++
			continue
		}

		switch c {
		case opAdd, opSub, opMul, opDiv, opRem:
			// All binary operators are left-associative, so reduce while the
			// pending operator binds at least as tightly.
			p := precedence(c)
			for len(e.ops) > 0 {
				top := e.ops[len(e.ops)-1]
				if top == opParen || precedence(top) < p {
					break
				}
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			e.ops = append(e.ops, c)
			expectOperand = true
		case ')':
			if err := e.reduceToParen(); err != nil {
				return 0, err
			}
		default:
			return 0, errSyntax
		}
		i++
	}

	if expectOperand {
		return 0, errSyntax
	}
	for len(e.ops) > 0 {
		if e.ops[len(e.ops)-1] == opParen {
			return 0, errSyntax // unclosed '('
		}
		if err := e.reduce(); err != nil {
			return 0, err
		}
	}
	if len(e.vals) != 1 {
		return 0, errSyntax
	}
	return e.vals[0], nil
}

// reduceToParen applies operators down to the nearest '(' and discards it.
func (e *evaluator) reduceToParen() error {
	for len(e.ops) > 0 {
		if e.ops[len(e.ops)-1] == opParen {
			e.ops = e.ops[:len(e.ops)-1]
			return nil
		}
		if err := e.reduce(); err != nil {
			return err
		}
	}
	return errSyntax // unmatched ')'
}

// reduce pops the top operator and applies it to the top of the value stack.
func (e *evaluator) reduce() error {
	op := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]

	n := len(e.vals)
	if op == opNeg {
		if n < 1 {
			return errSyntax
		}
		v := e.vals[n-1]
		if v == math.MinInt64 {
			return errOverflow
		}
		e.vals[n-1] = -v
		return nil
	}

	if n < 2 {
		return errSyntax
	}
	r, err := apply(op, e.vals[n-2], e.vals[n-1])
	if err != nil {
		return err
	}
	e.vals[n-2] = r
	e.vals = e.vals[:n-1]
	return nil
}

func precedence(op byte) int {
	switch op {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opRem:
		return 2
	case opNeg:
		return 3
	}
	return 0
}

// apply computes a op b, reporting division by zero and any result outside
// the int64 range.
func apply(op byte, a, b int64) (int64, error) {
	switch op {
	case opAdd:
		r := a + b
		if (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, errOverflow
		}
		return r, nil
	case opSub:
		r := a - b
		if (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, errOverflow
		}
		return r, nil
	case opMul:
		if a == 0 || b == 0 {
			return 0, nil
		}
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
			return 0, errOverflow
		}
		r := a * b
		if r/b != a {
			return 0, errOverflow
		}
		return r, nil
	case opDiv:
		if b == 0 {
			return 0, errDivZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, errOverflow
		}
		return a / b, nil
	case opRem:
		if b == 0 {
			return 0, errDivZero
		}
		if b == -1 {
			return 0, nil // exact result is 0 even for MinInt64
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + strconv.QuoteRune(rune(op)))
}

// parseNumber parses the maximal run of decimal digits at the start of s,
// returning its value and length. It fails if the literal exceeds MaxInt64.
func parseNumber(s []byte) (int64, int, error) {
	var v int64
	i := 0
	for ; i < len(s) && isDigit(s[i]); i++ {
		d := int64(s[i] - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, 0, errOverflow
		}
		v = v*10 + d
	}
	return v, i, nil
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }
