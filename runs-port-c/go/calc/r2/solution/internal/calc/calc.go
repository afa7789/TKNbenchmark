// Package calc evaluates 64-bit signed integer arithmetic expressions.
//
// Grammar (blanks — spaces and tabs — may appear between tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Evaluation uses an iterative operator-precedence (shunting-yard) algorithm
// with explicit stacks, so arbitrarily deep nesting cannot exhaust the call
// stack.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Evaluate.
var (
	ErrSyntax   = errors.New("syntax error")
	ErrOverflow = errors.New("integer overflow")
	ErrDivZero  = errors.New("division by zero")
)

// op is an operator code held on the operator stack.
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

// precedence reports how tightly op binds; '(' never reduces by precedence.
func (o op) precedence() int {
	switch o {
	case opNeg:
		return 3
	case opMul, opDiv, opMod:
		return 2
	case opAdd, opSub:
		return 1
	default:
		return 0
	}
}

// Evaluator evaluates expressions. Its zero value is ready to use. It reuses
// its internal stacks between calls, so reusing one Evaluator across many
// expressions avoids repeated allocation. An Evaluator is not safe for
// concurrent use.
type Evaluator struct {
	vals []int64
	ops  []op
}

// Evaluate returns the value of the expression in line.
func (e *Evaluator) Evaluate(line []byte) (int64, error) {
	e.vals = e.vals[:0]
	e.ops = e.ops[:0]

	wantOperand := true
	i, n := 0, len(line)
	for {
		for i < n && isBlank(line[i]) {
			i++
		}

		if wantOperand {
			if i == n {
				return 0, ErrSyntax
			}
			switch c := line[i]; {
			case c == '-':
				e.ops = append(e.ops, opNeg)
				i++
			case c == '(':
				e.ops = append(e.ops, opLParen)
				i++
			case isDigit(c):
				v, next, err := parseNumber(line, i)
				if err != nil {
					return 0, err
				}
				e.vals = append(e.vals, v)
				i = next
				wantOperand = false
			default:
				return 0, ErrSyntax
			}
			continue
		}

		if i == n {
			break
		}

		switch c := op(line[i]); c {
		case ')':
			if err := e.reduceWhile(0); err != nil {
				return 0, err
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax // unmatched ')'
			}
			e.ops = e.ops[:len(e.ops)-1] // discard '('
		case opAdd, opSub, opMul, opDiv, opMod:
			if err := e.reduceWhile(c.precedence()); err != nil {
				return 0, err
			}
			e.ops = append(e.ops, c)
			wantOperand = true
		default:
			return 0, ErrSyntax
		}
		i++
	}

	if err := e.reduceWhile(0); err != nil {
		return 0, err
	}
	if len(e.ops) != 0 {
		return 0, ErrSyntax // unmatched '('
	}
	return e.vals[0], nil
}

// parseNumber parses the decimal literal starting at line[i] and returns its
// value and the index just past it.
func parseNumber(line []byte, i int) (int64, int, error) {
	var v int64
	overflow := false
	for ; i < len(line) && isDigit(line[i]); i++ {
		d := int64(line[i] - '0')
		if v > (math.MaxInt64-d)/10 {
			overflow = true
		} else {
			v = v*10 + d
		}
	}
	if overflow {
		return 0, i, ErrOverflow
	}
	return v, i, nil
}

// reduceWhile reduces while the top operator binds at least as tightly as prec.
func (e *Evaluator) reduceWhile(prec int) error {
	for len(e.ops) > 0 {
		top := e.ops[len(e.ops)-1]
		if top == opLParen || top.precedence() < prec {
			break
		}
		if err := e.reduceOne(); err != nil {
			return err
		}
	}
	return nil
}

// reduceOne pops the top operator and applies it to the value stack.
func (e *Evaluator) reduceOne() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]

	top := len(e.vals) - 1
	if o == opNeg {
		if e.vals[top] == math.MinInt64 {
			return ErrOverflow
		}
		e.vals[top] = -e.vals[top]
		return nil
	}

	r, err := applyBinary(o, e.vals[top-1], e.vals[top])
	if err != nil {
		return err
	}
	e.vals = e.vals[:top]
	e.vals[top-1] = r
	return nil
}

// applyBinary applies a binary operator, detecting overflow and division by zero.
func applyBinary(o op, a, b int64) (int64, error) {
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
	case opMod:
		if b == 0 {
			return 0, ErrDivZero
		}
		if b == -1 {
			return 0, nil
		}
		return a % b, nil
	default:
		panic("calc: unknown operator " + string(rune(o)))
	}
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// IsBlank reports whether line is empty or contains only spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}
