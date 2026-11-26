// Package calc evaluates 64-bit signed integer arithmetic expressions.
//
// Grammar (spaces and tabs may appear between tokens):
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
)

// Errors returned by Evaluate.
var (
	ErrSyntax       = errors.New("syntax error")
	ErrDivideByZero = errors.New("division by zero")
	ErrOverflow     = errors.New("integer overflow")
)

// op is an entry on the operator stack.
type op byte

const (
	opLParen op = '('
	opNeg    op = 'n'
	opAdd    op = '+'
	opSub    op = '-'
	opMul    op = '*'
	opDiv    op = '/'
	opRem    op = '%'
)

// precedence returns the binding strength of o; '(' binds weakest so that
// reductions stop at it.
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

// evaluator is an operator-precedence (shunting-yard) evaluator. It is
// iterative, so deeply nested input cannot exhaust the stack.
type evaluator struct {
	values []int64
	ops    []op
}

func (e *evaluator) reduceTop() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]
	n := len(e.values)
	if o == opNeg {
		v, err := neg(e.values[n-1])
		e.values[n-1] = v
		return err
	}
	v, err := apply(o, e.values[n-2], e.values[n-1])
	e.values = e.values[:n-1]
	e.values[n-2] = v
	return err
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// Evaluate parses and evaluates a single expression.
func Evaluate(line []byte) (int64, error) {
	e := evaluator{}
	expectOperand := true

	for i := 0; i < len(line); {
		c := line[i]
		if isBlank(c) {
			i++
			continue
		}

		if isDigit(c) {
			if !expectOperand {
				return 0, ErrSyntax
			}
			start := i
			for i < len(line) && isDigit(line[i]) {
				i++
			}
			v, err := parseLiteral(line[start:i])
			if err != nil {
				return 0, err
			}
			e.values = append(e.values, v)
			expectOperand = false
			continue
		}
		i++

		if expectOperand {
			switch c {
			case '-':
				e.ops = append(e.ops, opNeg)
			case '(':
				e.ops = append(e.ops, opLParen)
			default:
				return 0, ErrSyntax
			}
			continue
		}

		switch o := op(c); o {
		case ')':
			for len(e.ops) > 0 && e.ops[len(e.ops)-1] != opLParen {
				if err := e.reduceTop(); err != nil {
					return 0, err
				}
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax
			}
			e.ops = e.ops[:len(e.ops)-1]
		case opAdd, opSub, opMul, opDiv, opRem:
			// Left-associative: reduce operators of equal or higher precedence.
			prec := o.precedence()
			for len(e.ops) > 0 && e.ops[len(e.ops)-1].precedence() >= prec {
				if err := e.reduceTop(); err != nil {
					return 0, err
				}
			}
			e.ops = append(e.ops, o)
			expectOperand = true
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
		if err := e.reduceTop(); err != nil {
			return 0, err
		}
	}
	return e.values[0], nil
}

// parseLiteral converts a run of ASCII digits to an int64.
func parseLiteral(digits []byte) (int64, error) {
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

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}

// apply evaluates a binary operator with overflow and division checks.
// Division truncates toward zero and the remainder takes the dividend's sign.
func apply(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		r := a + b
		if (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return r, nil
	case opSub:
		r := a - b
		if (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return r, nil
	case opMul:
		if a == 0 || b == 0 {
			return 0, nil
		}
		r := a * b
		if r/b != a || (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
			return 0, ErrOverflow
		}
		return r, nil
	case opDiv:
		if b == 0 {
			return 0, ErrDivideByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case opRem:
		if b == 0 {
			return 0, ErrDivideByZero
		}
		if b == -1 {
			// Always 0; also avoids MinInt64 % -1 on hardware that traps.
			return 0, nil
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(rune(o)))
}
