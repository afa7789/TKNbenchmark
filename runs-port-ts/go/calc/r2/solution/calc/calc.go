// Package calc evaluates signed 64-bit integer expressions.
//
// Grammar (spaces and tabs may appear between tokens):
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
	"strconv"
)

// Errors returned by Evaluate.
var (
	ErrSyntax    = errors.New("syntax error")
	ErrDivByZero = errors.New("division by zero")
	ErrOverflow  = errors.New("integer overflow")
)

// op is an operator held on the operator stack.
type op byte

const (
	opNeg    op = 'n'
	opLParen op = '('
)

func precedence(o op) int {
	switch o {
	case '+', '-':
		return 1
	case '*', '/', '%':
		return 2
	}
	return 0
}

func isBinary(c byte) bool {
	return c == '+' || c == '-' || c == '*' || c == '/' || c == '%'
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// IsBlank reports whether line contains only spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if !isSpace(c) {
			return false
		}
	}
	return true
}

func add(a, b int64) (int64, error) {
	s := a + b
	if (a >= 0) == (b >= 0) && (s >= 0) != (a >= 0) {
		return 0, ErrOverflow
	}
	return s, nil
}

func sub(a, b int64) (int64, error) {
	d := a - b
	if (a >= 0) != (b >= 0) && (d >= 0) != (a >= 0) {
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
	return a / b, nil
}

func rem(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivByZero
	}
	if b == -1 {
		return 0, nil // avoids MinInt64 % -1 trapping on some platforms
	}
	return a % b, nil
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}

func apply(o op, a, b int64) (int64, error) {
	switch o {
	case '+':
		return add(a, b)
	case '-':
		return sub(a, b)
	case '*':
		return mul(a, b)
	case '/':
		return div(a, b)
	case '%':
		return rem(a, b)
	}
	panic("calc: unknown operator " + string(o))
}

// evaluator holds the operand and operator stacks for a single evaluation.
type evaluator struct {
	values []int64
	ops    []op
}

// reduce pops the top operator and applies it to the operand stack.
func (e *evaluator) reduce() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]
	n := len(e.values)
	switch o {
	case opLParen:
		return nil
	case opNeg:
		v, err := neg(e.values[n-1])
		if err != nil {
			return err
		}
		e.values[n-1] = v
		return nil
	}
	v, err := apply(o, e.values[n-2], e.values[n-1])
	if err != nil {
		return err
	}
	e.values = e.values[:n-1]
	e.values[n-2] = v
	return nil
}

// Evaluate parses and evaluates one expression.
func Evaluate(src []byte) (int64, error) {
	var e evaluator
	expectOperand := true

	for i := 0; i < len(src); {
		c := src[i]
		switch {
		case isSpace(c):
			i++

		case isDigit(c):
			if !expectOperand {
				return 0, ErrSyntax
			}
			start := i
			for i < len(src) && isDigit(src[i]) {
				i++
			}
			v, err := strconv.ParseInt(string(src[start:i]), 10, 64)
			if err != nil {
				return 0, ErrOverflow
			}
			e.values = append(e.values, v)
			expectOperand = false

		case expectOperand:
			i++
			switch c {
			case '-':
				e.ops = append(e.ops, opNeg)
			case '(':
				e.ops = append(e.ops, opLParen)
			default:
				return 0, ErrSyntax
			}

		case isBinary(c):
			i++
			o := op(c)
			prec := precedence(o)
			for len(e.ops) > 0 {
				top := e.ops[len(e.ops)-1]
				if top == opLParen || (top != opNeg && precedence(top) < prec) {
					break
				}
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			e.ops = append(e.ops, o)
			expectOperand = true

		case c == ')':
			i++
			for {
				if len(e.ops) == 0 {
					return 0, ErrSyntax
				}
				if e.ops[len(e.ops)-1] == opLParen {
					break
				}
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			e.ops = e.ops[:len(e.ops)-1]

		default:
			return 0, ErrSyntax
		}
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
