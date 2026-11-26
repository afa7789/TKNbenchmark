package main

import (
	"errors"
	"math"
)

// Errors reported by Evaluate. Callers that only need to know whether an
// expression is valid can compare against nil; the distinct values exist
// for diagnostics and tests.
var (
	ErrSyntax       = errors.New("syntax error")
	ErrDivideByZero = errors.New("division by zero")
	ErrOverflow     = errors.New("overflow")
)

// op is an entry on the operator stack.
type op byte

const (
	opAdd    op = '+'
	opSub    op = '-'
	opMul    op = '*'
	opDiv    op = '/'
	opRem    op = '%'
	opNeg    op = 'n' // unary minus
	opLParen op = '('
)

// precedence returns the binding strength of an operator on the stack, or 0
// for anything that is not an operator. Unary minus binds tighter than every
// binary operator.
func precedence(o op) int {
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

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// Evaluate parses and evaluates one expression as signed 64-bit integer
// arithmetic, following the grammar in SPEC.md.
//
// It uses an iterative operator-precedence (shunting-yard) parser, so deeply
// nested input cannot exhaust the stack.
func Evaluate(line string) (int64, error) {
	var (
		values []int64
		ops    []op
	)

	reduceTop := func() error {
		o := ops[len(ops)-1]
		ops = ops[:len(ops)-1]
		if o == opNeg {
			v, err := neg(values[len(values)-1])
			if err != nil {
				return err
			}
			values[len(values)-1] = v
			return nil
		}
		a, b := values[len(values)-2], values[len(values)-1]
		values = values[:len(values)-1]
		v, err := applyBinary(o, a, b)
		if err != nil {
			return err
		}
		values[len(values)-1] = v
		return nil
	}

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
				for j < len(line) && isDigit(line[j]) {
					j++
				}
				v, err := parseLiteral(line[i:j])
				if err != nil {
					return 0, err
				}
				values = append(values, v)
				expectOperand = false
				i = j
				continue
			case c == '-':
				ops = append(ops, opNeg)
			case c == '(':
				ops = append(ops, opLParen)
			default:
				return 0, ErrSyntax
			}

		case c == ')':
			for len(ops) > 0 && ops[len(ops)-1] != opLParen {
				if err := reduceTop(); err != nil {
					return 0, err
				}
			}
			if len(ops) == 0 {
				return 0, ErrSyntax
			}
			ops = ops[:len(ops)-1]

		default:
			o := op(c)
			p := precedence(o)
			if p == 0 || o == opNeg {
				return 0, ErrSyntax
			}
			// Left-associative: reduce everything binding at least as
			// tightly before pushing this operator.
			for len(ops) > 0 && precedence(ops[len(ops)-1]) >= p {
				if err := reduceTop(); err != nil {
					return 0, err
				}
			}
			ops = append(ops, o)
			expectOperand = true
		}
		i++
	}

	if expectOperand {
		return 0, ErrSyntax
	}
	for len(ops) > 0 {
		if ops[len(ops)-1] == opLParen {
			return 0, ErrSyntax
		}
		if err := reduceTop(); err != nil {
			return 0, err
		}
	}
	return values[0], nil
}

// parseLiteral converts a non-empty run of ASCII digits to an int64.
func parseLiteral(digits string) (int64, error) {
	var v int64
	for i := 0; i < len(digits); i++ {
		d := int64(digits[i] - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, ErrOverflow
		}
		v = v*10 + d
	}
	return v, nil
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}

func applyBinary(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		r := a + b
		if (a^r)&(b^r) < 0 {
			return 0, ErrOverflow
		}
		return r, nil
	case opSub:
		r := a - b
		if (a^b)&(a^r) < 0 {
			return 0, ErrOverflow
		}
		return r, nil
	case opMul:
		if a == 0 || b == 0 {
			return 0, nil
		}
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
			return 0, ErrOverflow
		}
		r := a * b
		if r/b != a {
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
		return a / b, nil // Go's division truncates toward zero.
	case opRem:
		if b == 0 {
			return 0, ErrDivideByZero
		}
		if b == -1 {
			return 0, nil // Avoids MinInt64 % -1 edge cases; the result is always 0.
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(rune(o)))
}
