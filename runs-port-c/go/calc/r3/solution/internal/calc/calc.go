// Package calc evaluates 64-bit signed integer expressions.
//
// Grammar (spaces and tabs may appear between any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Parsing uses an explicit-stack operator-precedence algorithm, so
// arbitrarily deep nesting cannot exhaust the call stack.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Evaluate.
var (
	ErrSyntax       = errors.New("syntax error")
	ErrDivideByZero = errors.New("division by zero")
	ErrOverflow     = errors.New("integer overflow")
)

type op uint8

const (
	opLParen op = iota
	opAdd
	opSub
	opMul
	opDiv
	opMod
	opNeg
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

// Evaluator evaluates expressions. Its zero value is ready to use; reusing
// one Evaluator across calls avoids reallocating its working stacks.
// An Evaluator is not safe for concurrent use.
type Evaluator struct {
	vals []int64
	ops  []op
}

// Evaluate is a convenience wrapper that evaluates expr with a fresh Evaluator.
func Evaluate(expr []byte) (int64, error) {
	var ev Evaluator
	return ev.Evaluate(expr)
}

// Evaluate parses and evaluates expr, returning its value or an error
// describing why the expression has no value.
func (ev *Evaluator) Evaluate(expr []byte) (int64, error) {
	vals, ops := ev.vals[:0], ev.ops[:0]
	defer func() { ev.vals, ev.ops = vals[:0], ops[:0] }()

	// apply pops the top operator and applies it to the value stack.
	apply := func() error {
		o := ops[len(ops)-1]
		ops = ops[:len(ops)-1]
		if o == opNeg {
			top := &vals[len(vals)-1]
			r, err := neg(*top)
			*top = r
			return err
		}
		b := vals[len(vals)-1]
		vals = vals[:len(vals)-1]
		a := &vals[len(vals)-1]
		r, err := binary(o, *a, b)
		*a = r
		return err
	}

	wantOperand := true
	for i := 0; i < len(expr); {
		c := expr[i]
		if isBlank(c) {
			i++
			continue
		}

		if wantOperand {
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
				vals = append(vals, v)
				wantOperand = false
				continue
			case c == '-':
				ops = append(ops, opNeg)
			case c == '(':
				ops = append(ops, opLParen)
			default:
				return 0, ErrSyntax
			}
			i++
			continue
		}

		var o op
		switch c {
		case '+':
			o = opAdd
		case '-':
			o = opSub
		case '*':
			o = opMul
		case '/':
			o = opDiv
		case '%':
			o = opMod
		case ')':
			for len(ops) > 0 && ops[len(ops)-1] != opLParen {
				if err := apply(); err != nil {
					return 0, err
				}
			}
			if len(ops) == 0 {
				return 0, ErrSyntax
			}
			ops = ops[:len(ops)-1]
			i++
			continue
		default:
			return 0, ErrSyntax
		}

		// All binary operators are left-associative.
		prec := o.precedence()
		for len(ops) > 0 && ops[len(ops)-1].precedence() >= prec {
			if err := apply(); err != nil {
				return 0, err
			}
		}
		ops = append(ops, o)
		wantOperand = true
		i++
	}

	if wantOperand {
		return 0, ErrSyntax
	}
	for len(ops) > 0 {
		if ops[len(ops)-1] == opLParen {
			return 0, ErrSyntax
		}
		if err := apply(); err != nil {
			return 0, err
		}
	}
	return vals[0], nil
}

// IsBlank reports whether line consists only of spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

func binary(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		return add(a, b)
	case opSub:
		return sub(a, b)
	case opMul:
		return mul(a, b)
	case opDiv:
		return div(a, b)
	case opMod:
		return mod(a, b)
	}
	panic("calc: invalid binary operator")
}

// ---------- checked 64-bit arithmetic ----------

func add(a, b int64) (int64, error) {
	r := a + b
	if (r > a) != (b > 0) {
		return 0, ErrOverflow
	}
	return r, nil
}

func sub(a, b int64) (int64, error) {
	r := a - b
	if (r < a) != (b > 0) {
		return 0, ErrOverflow
	}
	return r, nil
}

func mul(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	r := a * b
	if r/b != a || (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
		return 0, ErrOverflow
	}
	return r, nil
}

func div(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivideByZero
	}
	if a == math.MinInt64 && b == -1 {
		return 0, ErrOverflow
	}
	return a / b, nil
}

func mod(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivideByZero
	}
	return a % b, nil // Go defines MinInt64 % -1 as 0.
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}
