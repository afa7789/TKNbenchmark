// Package calc evaluates signed 64-bit integer arithmetic expressions.
//
// Grammar (spaces and tabs may appear between any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
package calc

import (
	"errors"
	"math"
	"strconv"
)

var (
	// ErrBlank reports that the input holds no tokens.
	ErrBlank = errors.New("blank expression")
	// ErrSyntax reports input that does not match the grammar.
	ErrSyntax = errors.New("syntax error")
	// ErrDivisionByZero reports a division or remainder by zero.
	ErrDivisionByZero = errors.New("division by zero")
	// ErrOverflow reports a literal or result outside the int64 range.
	ErrOverflow = errors.New("overflow")
)

// op is an entry on the operator stack. Binary operators are stored as
// their ASCII character; the other values are below any printable byte.
type op byte

const (
	opLParen op = iota
	opNegate
)

func precedence(o op) int {
	switch o {
	case '+', '-':
		return 1
	case '*', '/', '%':
		return 2
	case opNegate:
		return 3
	default:
		return 0
	}
}

// evaluator holds the operand and operator stacks of an
// operator-precedence parser. Parsing is iterative so arbitrarily deep
// nesting cannot exhaust the call stack.
type evaluator struct {
	values []int64
	ops    []op
}

// Evaluate parses and evaluates expr. It returns ErrBlank when expr is
// empty or holds only spaces and tabs, and ErrSyntax, ErrDivisionByZero
// or ErrOverflow when the expression has no valid value.
func Evaluate(expr []byte) (int64, error) {
	var e evaluator
	return e.evaluate(expr)
}

func (e *evaluator) evaluate(s []byte) (int64, error) {
	expectOperand := true
	sawToken := false

	for i := 0; i < len(s); {
		c := s[i]
		if c == ' ' || c == '\t' {
			i++
			continue
		}
		sawToken = true

		if expectOperand {
			switch {
			case isDigit(c):
				start := i
				for i < len(s) && isDigit(s[i]) {
					i++
				}
				v, err := strconv.ParseInt(string(s[start:i]), 10, 64)
				if err != nil {
					return 0, ErrOverflow
				}
				e.values = append(e.values, v)
				expectOperand = false
				continue
			case c == '-':
				e.ops = append(e.ops, opNegate)
			case c == '(':
				e.ops = append(e.ops, opLParen)
			default:
				return 0, ErrSyntax
			}
			i++
			continue
		}

		switch c {
		case '+', '-', '*', '/', '%':
			// All binary operators are left-associative.
			p := precedence(op(c))
			for len(e.ops) > 0 && precedence(e.ops[len(e.ops)-1]) >= p {
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			e.ops = append(e.ops, op(c))
			expectOperand = true
		case ')':
			for len(e.ops) > 0 && e.ops[len(e.ops)-1] != opLParen {
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax
			}
			e.ops = e.ops[:len(e.ops)-1]
		default:
			return 0, ErrSyntax
		}
		i++
	}

	if !sawToken {
		return 0, ErrBlank
	}
	if expectOperand {
		return 0, ErrSyntax
	}
	for len(e.ops) > 0 {
		if e.ops[len(e.ops)-1] == opLParen {
			return 0, ErrSyntax
		}
		if err := e.reduce(); err != nil {
			return 0, err
		}
	}
	return e.values[0], nil
}

// reduce pops the top operator and applies it to the operand stack.
func (e *evaluator) reduce() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]
	n := len(e.values)

	if o == opNegate {
		v := e.values[n-1]
		if v == math.MinInt64 {
			return ErrOverflow
		}
		e.values[n-1] = -v
		return nil
	}

	r, err := apply(o, e.values[n-2], e.values[n-1])
	if err != nil {
		return err
	}
	e.values[n-2] = r
	e.values = e.values[:n-1]
	return nil
}

func apply(o op, a, b int64) (int64, error) {
	switch o {
	case '+':
		r := a + b
		if (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return r, nil
	case '-':
		r := a - b
		if (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return r, nil
	case '*':
		if a == 0 || b == 0 {
			return 0, nil
		}
		r := a * b
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || r/b != a {
			return 0, ErrOverflow
		}
		return r, nil
	case '/':
		if b == 0 {
			return 0, ErrDivisionByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil // Go division truncates toward zero.
	case '%':
		if b == 0 {
			return 0, ErrDivisionByZero
		}
		return a % b, nil // Sign follows the dividend; MinInt64 % -1 is 0.
	default:
		panic("calc: unknown operator " + strconv.QuoteRune(rune(o)))
	}
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
