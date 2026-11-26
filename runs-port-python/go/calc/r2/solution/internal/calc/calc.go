// Package calc evaluates arithmetic expressions over signed 64-bit integers.
//
// Grammar (spaces and tabs may separate any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Parsing uses an explicit operator stack (shunting-yard), so deeply nested
// input cannot exhaust the goroutine stack.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Eval.
var (
	ErrSyntax   = errors.New("syntax error")
	ErrDivZero  = errors.New("division by zero")
	ErrOverflow = errors.New("integer overflow")
)

type op byte

const (
	opLParen op = '('
	opNeg    op = '~'
	opAdd    op = '+'
	opSub    op = '-'
	opMul    op = '*'
	opDiv    op = '/'
	opRem    op = '%'
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

// IsBlank reports whether line consists only of spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Evaluator evaluates expressions. Its zero value is ready to use; reusing one
// Evaluator across calls avoids reallocating its internal stacks. An
// Evaluator is not safe for concurrent use.
type Evaluator struct {
	values []int64
	ops    []op
}

// Eval evaluates a single expression.
func Eval(expr []byte) (int64, error) {
	var e Evaluator
	return e.Eval(expr)
}

// Eval evaluates a single expression. It returns ErrSyntax, ErrDivZero or
// ErrOverflow if the expression is malformed or cannot be evaluated exactly.
func (e *Evaluator) Eval(expr []byte) (int64, error) {
	e.values = e.values[:0]
	e.ops = e.ops[:0]
	expectOperand := true

	for i := 0; i < len(expr); {
		c := expr[i]
		switch {
		case c == ' ' || c == '\t':
			i++
			continue

		case isDigit(c):
			if !expectOperand {
				return 0, ErrSyntax
			}
			j := i
			for j < len(expr) && isDigit(expr[j]) {
				j++
			}
			v, err := parseNumber(expr[i:j])
			if err != nil {
				return 0, err
			}
			e.values = append(e.values, v)
			expectOperand = false
			i = j
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

		switch c {
		case ')':
			for len(e.ops) > 0 && e.top() != opLParen {
				if err := e.applyTop(); err != nil {
					return 0, err
				}
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax
			}
			e.ops = e.ops[:len(e.ops)-1]
		case '+', '-', '*', '/', '%':
			o := op(c)
			for len(e.ops) > 0 && e.top() != opLParen && e.top().precedence() >= o.precedence() {
				if err := e.applyTop(); err != nil {
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
		if e.top() == opLParen {
			return 0, ErrSyntax
		}
		if err := e.applyTop(); err != nil {
			return 0, err
		}
	}
	return e.values[0], nil
}

func (e *Evaluator) top() op { return e.ops[len(e.ops)-1] }

// applyTop pops the top operator and applies it to the value stack.
func (e *Evaluator) applyTop() error {
	o := e.top()
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

	v, err := binary(o, e.values[n-2], e.values[n-1])
	if err != nil {
		return err
	}
	e.values[n-2] = v
	e.values = e.values[:n-1]
	return nil
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// parseNumber converts a non-empty run of ASCII digits, which may have
// leading zeros, to an int64.
func parseNumber(digits []byte) (int64, error) {
	var v int64
	for _, d := range digits {
		x := int64(d - '0')
		if v > (math.MaxInt64-x)/10 {
			return 0, ErrOverflow
		}
		v = v*10 + x
	}
	return v, nil
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}

func binary(o op, a, b int64) (int64, error) {
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
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || r/b != a {
			return 0, ErrOverflow
		}
		return r, nil
	case opDiv:
		if b == 0 {
			return 0, ErrDivZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case opRem:
		if b == 0 {
			return 0, ErrDivZero
		}
		if b == -1 {
			return 0, nil // avoids MinInt64 % -1 edge case; result is always 0
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(o))
}
