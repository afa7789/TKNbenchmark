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
)

// Errors returned by Eval.
var (
	ErrSyntax         = errors.New("syntax error")
	ErrUnbalanced     = errors.New("unbalanced parentheses")
	ErrMissingOperand = errors.New("missing operand")
	ErrDivByZero      = errors.New("division by zero")
	ErrOverflow       = errors.New("overflow")
)

// op is an operator on the shunting-yard stack.
type op byte

const (
	opLParen op = '('
	opNeg    op = 'n'
	opAdd    op = '+'
	opSub    op = '-'
	opMul    op = '*'
	opDiv    op = '/'
	opMod    op = '%'
)

func (o op) precedence() int {
	switch o {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opMod:
		return 2
	case opNeg:
		return 3
	}
	return 0
}

func isBinary(c byte) bool {
	switch op(c) {
	case opAdd, opSub, opMul, opDiv, opMod:
		return true
	}
	return false
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
func isBlank(c byte) bool { return c == ' ' || c == '\t' }

// IsBlank reports whether line is empty or holds only spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}

// Eval evaluates a single expression. It uses an operator-precedence
// (shunting-yard) parser, so deeply nested input cannot exhaust the stack.
func Eval(line []byte) (int64, error) {
	var e evaluator
	return e.eval(line)
}

type evaluator struct {
	values []int64
	ops    []op
}

func (e *evaluator) eval(line []byte) (int64, error) {
	expectOperand := true
	for i := 0; i < len(line); {
		c := line[i]
		switch {
		case isBlank(c):
			i++
			continue
		case expectOperand:
			switch {
			case isDigit(c):
				j := i
				var v int64
				for ; j < len(line) && isDigit(line[j]); j++ {
					d := int64(line[j] - '0')
					if v > (math.MaxInt64-d)/10 {
						return 0, ErrOverflow
					}
					v = v*10 + d
				}
				e.values = append(e.values, v)
				i = j
				expectOperand = false
				continue
			case c == '-':
				e.ops = append(e.ops, opNeg)
			case c == '(':
				e.ops = append(e.ops, opLParen)
			default:
				return 0, ErrSyntax
			}
		case isBinary(c):
			o := op(c)
			for len(e.ops) > 0 {
				top := e.ops[len(e.ops)-1]
				if top == opLParen || top.precedence() < o.precedence() {
					break
				}
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			e.ops = append(e.ops, o)
			expectOperand = true
		case c == ')':
			for len(e.ops) > 0 && e.ops[len(e.ops)-1] != opLParen {
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			if len(e.ops) == 0 {
				return 0, ErrUnbalanced
			}
			e.ops = e.ops[:len(e.ops)-1]
		default:
			return 0, ErrSyntax
		}
		i++
	}

	if expectOperand {
		return 0, ErrMissingOperand
	}
	for len(e.ops) > 0 {
		if e.ops[len(e.ops)-1] == opLParen {
			return 0, ErrUnbalanced
		}
		if err := e.reduce(); err != nil {
			return 0, err
		}
	}
	return e.values[0], nil
}

// reduce pops one operator and applies it to the operand stack.
func (e *evaluator) reduce() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]

	n := len(e.values)
	if o == opNeg {
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

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}

func apply(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		s := a + b
		if (a >= 0) == (b >= 0) && (s >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return s, nil
	case opSub:
		d := a - b
		if (a >= 0) != (b >= 0) && (d >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return d, nil
	case opMul:
		if a == 0 || b == 0 {
			return 0, nil
		}
		p := a * b
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || p/b != a {
			return 0, ErrOverflow
		}
		return p, nil
	case opDiv:
		if b == 0 {
			return 0, ErrDivByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case opMod:
		if b == 0 {
			return 0, ErrDivByZero
		}
		if b == -1 {
			return 0, nil // avoids MinInt64 % -1; the result is always 0
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(o))
}
