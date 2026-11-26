// Package calc evaluates signed 64-bit integer arithmetic expressions.
//
// Grammar (spaces and tabs may separate any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Parsing is iterative (operator precedence with explicit stacks), so deeply
// nested input cannot exhaust the call stack.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Evaluate.
var (
	ErrSyntax      = errors.New("syntax error")
	ErrDivByZero   = errors.New("division by zero")
	ErrOverflow    = errors.New("integer overflow")
	errUnreachable = errors.New("internal: malformed operator stack")
)

type op byte

const (
	opAdd   op = '+'
	opSub   op = '-'
	opMul   op = '*'
	opDiv   op = '/'
	opRem   op = '%'
	opNeg   op = 'n'
	opParen op = '('
)

func (o op) precedence() int {
	switch o {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opRem:
		return 2
	case opNeg:
		return 3
	}
	return 0
}

// IsBlank reports whether line consists solely of spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Evaluate parses and evaluates a single expression. It returns ErrSyntax,
// ErrDivByZero or ErrOverflow on failure.
func Evaluate(src []byte) (int64, error) {
	var m machine
	expectOperand := true

	for i := 0; i < len(src); {
		c := src[i]
		switch {
		case c == ' ' || c == '\t':
			i++
			continue
		case isDigit(c):
			if !expectOperand {
				return 0, ErrSyntax
			}
			start := i
			for i < len(src) && isDigit(src[i]) {
				i++
			}
			v, err := parseNumber(src[start:i])
			if err != nil {
				return 0, err
			}
			m.values = append(m.values, v)
			expectOperand = false
			continue
		}

		i++
		if expectOperand {
			switch c {
			case '-':
				m.ops = append(m.ops, opNeg)
			case '(':
				m.ops = append(m.ops, opParen)
			default:
				return 0, ErrSyntax
			}
			continue
		}

		switch o := op(c); o {
		case opAdd, opSub, opMul, opDiv, opRem:
			if err := m.pushBinary(o); err != nil {
				return 0, err
			}
			expectOperand = true
		case ')':
			if err := m.closeParen(); err != nil {
				return 0, err
			}
		default:
			return 0, ErrSyntax
		}
	}

	if expectOperand {
		return 0, ErrSyntax
	}
	return m.finish()
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// parseNumber converts a run of ASCII digits to int64, rejecting values
// above math.MaxInt64.
func parseNumber(digits []byte) (int64, error) {
	var v int64
	for _, d := range digits {
		n := int64(d - '0')
		if v > (math.MaxInt64-n)/10 {
			return 0, ErrOverflow
		}
		v = v*10 + n
	}
	return v, nil
}

// machine holds the operand and operator stacks of the shunting-yard parser.
type machine struct {
	values []int64
	ops    []op
}

// pushBinary reduces pending operators that bind at least as tightly as o
// (giving left associativity), then pushes o.
func (m *machine) pushBinary(o op) error {
	prec := o.precedence()
	for len(m.ops) > 0 {
		top := m.ops[len(m.ops)-1]
		if top == opParen || top.precedence() < prec {
			break
		}
		if err := m.reduce(); err != nil {
			return err
		}
	}
	m.ops = append(m.ops, o)
	return nil
}

// closeParen reduces up to and including the matching '('.
func (m *machine) closeParen() error {
	for len(m.ops) > 0 {
		if m.ops[len(m.ops)-1] == opParen {
			m.ops = m.ops[:len(m.ops)-1]
			return nil
		}
		if err := m.reduce(); err != nil {
			return err
		}
	}
	return ErrSyntax
}

func (m *machine) finish() (int64, error) {
	for len(m.ops) > 0 {
		if m.ops[len(m.ops)-1] == opParen {
			return 0, ErrSyntax
		}
		if err := m.reduce(); err != nil {
			return 0, err
		}
	}
	if len(m.values) != 1 {
		return 0, ErrSyntax
	}
	return m.values[0], nil
}

// reduce pops the top operator and applies it to the top operand(s).
func (m *machine) reduce() error {
	o := m.ops[len(m.ops)-1]
	m.ops = m.ops[:len(m.ops)-1]

	if o == opNeg {
		n := len(m.values)
		if n < 1 {
			return errUnreachable
		}
		v, err := neg(m.values[n-1])
		if err != nil {
			return err
		}
		m.values[n-1] = v
		return nil
	}

	n := len(m.values)
	if n < 2 {
		return errUnreachable
	}
	v, err := apply(o, m.values[n-2], m.values[n-1])
	if err != nil {
		return err
	}
	m.values[n-2] = v
	m.values = m.values[:n-1]
	return nil
}

func apply(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		return add(a, b)
	case opSub:
		return sub(a, b)
	case opMul:
		return mul(a, b)
	case opDiv:
		return div(a, b)
	case opRem:
		return rem(a, b)
	}
	return 0, errUnreachable
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}

func add(a, b int64) (int64, error) {
	s := a + b
	// Overflow iff both operands share a sign that differs from the sum's.
	if (a^s)&(b^s) < 0 {
		return 0, ErrOverflow
	}
	return s, nil
}

func sub(a, b int64) (int64, error) {
	d := a - b
	// Overflow iff the operands differ in sign and the result's sign differs from a's.
	if (a^b)&(a^d) < 0 {
		return 0, ErrOverflow
	}
	return d, nil
}

func mul(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	p := a * b
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || p/b != a {
		return 0, ErrOverflow
	}
	return p, nil
}

func div(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivByZero
	}
	if a == math.MinInt64 && b == -1 {
		return 0, ErrOverflow
	}
	return a / b, nil // Go division truncates toward zero.
}

func rem(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivByZero
	}
	if b == -1 {
		return 0, nil // Avoids MinInt64 % -1 trapping on some architectures.
	}
	return a % b, nil // Sign follows the dividend.
}
