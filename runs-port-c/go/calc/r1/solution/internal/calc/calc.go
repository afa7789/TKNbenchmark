// Package calc evaluates 64-bit signed integer arithmetic expressions.
//
// The evaluator is an iterative operator-precedence (shunting-yard) parser
// with explicit stacks, so arbitrarily deep nesting cannot exhaust the
// goroutine stack.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Evaluate.
var (
	ErrSyntax    = errors.New("syntax error")
	ErrDivByZero = errors.New("division by zero")
	ErrOverflow  = errors.New("integer overflow")
)

// op is an operator kept on the evaluator's operator stack.
type op byte

const (
	opAdd    op = '+'
	opSub    op = '-'
	opMul    op = '*'
	opDiv    op = '/'
	opRem    op = '%'
	opNeg    op = 'n'
	opLParen op = '('
)

// precedence returns the binding strength of o; '(' never pops.
func (o op) precedence() int {
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

// Evaluator evaluates expressions, reusing its internal stacks between
// calls to avoid repeated allocation. The zero value is ready to use.
// An Evaluator is not safe for concurrent use.
type Evaluator struct {
	values []int64
	ops    []op
}

// Evaluate parses and evaluates expr according to the grammar:
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Spaces and tabs may appear between tokens.
func (e *Evaluator) Evaluate(expr []byte) (int64, error) {
	e.values = e.values[:0]
	e.ops = e.ops[:0]

	expectOperand := true
	for i := 0; ; {
		for i < len(expr) && isBlank(expr[i]) {
			i++
		}
		if i == len(expr) {
			break
		}

		c := expr[i]
		if expectOperand {
			switch {
			case isDigit(c):
				var v int64
				for ; i < len(expr) && isDigit(expr[i]); i++ {
					d := int64(expr[i] - '0')
					if v > (math.MaxInt64-d)/10 {
						return 0, ErrOverflow
					}
					v = v*10 + d
				}
				e.values = append(e.values, v)
				expectOperand = false
			case c == '-':
				e.ops = append(e.ops, opNeg)
				i++
			case c == '(':
				e.ops = append(e.ops, opLParen)
				i++
			default:
				return 0, ErrSyntax
			}
			continue
		}

		switch o := op(c); o {
		case opAdd, opSub, opMul, opDiv, opRem:
			if err := e.reduce(o.precedence()); err != nil {
				return 0, err
			}
			e.ops = append(e.ops, o)
			expectOperand = true
		case ')':
			if err := e.reduce(0); err != nil {
				return 0, err
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax // unmatched ')'
			}
			e.ops = e.ops[:len(e.ops)-1] // discard '('
		default:
			return 0, ErrSyntax
		}
		i++
	}

	if expectOperand {
		return 0, ErrSyntax
	}
	if err := e.reduce(0); err != nil {
		return 0, err
	}
	if len(e.ops) != 0 || len(e.values) != 1 {
		return 0, ErrSyntax // unmatched '('
	}
	return e.values[0], nil
}

// reduce pops and applies operators whose precedence is at least minPrec.
func (e *Evaluator) reduce(minPrec int) error {
	for len(e.ops) > 0 {
		top := e.ops[len(e.ops)-1]
		if top == opLParen || top.precedence() < minPrec {
			return nil
		}
		e.ops = e.ops[:len(e.ops)-1]
		if err := e.apply(top); err != nil {
			return err
		}
	}
	return nil
}

// apply applies o to the operand(s) on top of the value stack.
func (e *Evaluator) apply(o op) error {
	n := len(e.values)
	if o == opNeg {
		if n < 1 {
			return ErrSyntax
		}
		v, err := neg(e.values[n-1])
		if err != nil {
			return err
		}
		e.values[n-1] = v
		return nil
	}
	if n < 2 {
		return ErrSyntax
	}
	a, b := e.values[n-2], e.values[n-1]
	var (
		r   int64
		err error
	)
	switch o {
	case opAdd:
		r, err = add(a, b)
	case opSub:
		r, err = sub(a, b)
	case opMul:
		r, err = mul(a, b)
	case opDiv:
		r, err = div(a, b)
	case opRem:
		r, err = rem(a, b)
	default:
		return ErrSyntax
	}
	if err != nil {
		return err
	}
	e.values = e.values[:n-1]
	e.values[n-2] = r
	return nil
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }
func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// IsBlank reports whether line consists only of spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}
