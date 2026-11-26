package main

import (
	"errors"
	"math"
)

// errCalc is returned for any condition that makes a line evaluate to "error".
var errCalc = errors.New("calc: invalid expression")

// op is an entry on the operator stack.
type op byte

const (
	opParen op = '('
	opNeg   op = 'n'
	opAdd   op = '+'
	opSub   op = '-'
	opMul   op = '*'
	opDiv   op = '/'
	opRem   op = '%'
)

func (o op) precedence() int {
	switch o {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opRem:
		return 2
	case opNeg:
		return 3
	default: // opParen
		return 0
	}
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func add(a, b int64) (int64, error) {
	r := a + b
	if (b > 0 && r < a) || (b < 0 && r > a) {
		return 0, errCalc
	}
	return r, nil
}

func sub(a, b int64) (int64, error) {
	r := a - b
	if (b > 0 && r > a) || (b < 0 && r < a) {
		return 0, errCalc
	}
	return r, nil
}

func mul(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
		return 0, errCalc
	}
	r := a * b
	if r/b != a {
		return 0, errCalc
	}
	return r, nil
}

func div(a, b int64) (int64, error) {
	if b == 0 || (a == math.MinInt64 && b == -1) {
		return 0, errCalc
	}
	return a / b, nil
}

func rem(a, b int64) (int64, error) {
	if b == 0 {
		return 0, errCalc
	}
	if b == -1 {
		return 0, nil // avoids MinInt64 % -1; the result is always 0
	}
	return a % b, nil
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, errCalc
	}
	return -a, nil
}

func applyBinary(o op, a, b int64) (int64, error) {
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
	return 0, errCalc
}

// parseNumber converts a run of ASCII digits to int64, rejecting overflow.
func parseNumber(digits []byte) (int64, error) {
	var v int64
	for _, c := range digits {
		d := int64(c - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, errCalc
		}
		v = v*10 + d
	}
	return v, nil
}

// evaluator holds the reusable stacks of an operator-precedence
// (shunting-yard) parser. Explicit stacks keep deeply nested input from
// exhausting the call stack.
type evaluator struct {
	values []int64
	ops    []op
}

func (e *evaluator) reduceTop() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]
	if o == opNeg {
		top := len(e.values) - 1
		v, err := neg(e.values[top])
		if err != nil {
			return err
		}
		e.values[top] = v
		return nil
	}
	n := len(e.values)
	v, err := applyBinary(o, e.values[n-2], e.values[n-1])
	if err != nil {
		return err
	}
	e.values[n-2] = v
	e.values = e.values[:n-1]
	return nil
}

// eval evaluates a single expression line.
func (e *evaluator) eval(line []byte) (int64, error) {
	e.values = e.values[:0]
	e.ops = e.ops[:0]
	expectOperand := true

	for i := 0; i < len(line); {
		c := line[i]
		if isBlank(c) {
			i++
			continue
		}

		if expectOperand {
			switch {
			case isDigit(c):
				j := i + 1
				for j < len(line) && isDigit(line[j]) {
					j++
				}
				v, err := parseNumber(line[i:j])
				if err != nil {
					return 0, err
				}
				e.values = append(e.values, v)
				i = j
				expectOperand = false
				continue
			case c == '-':
				e.ops = append(e.ops, opNeg)
			case c == '(':
				e.ops = append(e.ops, opParen)
			default:
				return 0, errCalc
			}
			i++
			continue
		}

		switch c {
		case ')':
			for len(e.ops) > 0 && e.ops[len(e.ops)-1] != opParen {
				if err := e.reduceTop(); err != nil {
					return 0, err
				}
			}
			if len(e.ops) == 0 {
				return 0, errCalc
			}
			e.ops = e.ops[:len(e.ops)-1]
		case '+', '-', '*', '/', '%':
			o := op(c)
			prec := o.precedence()
			for len(e.ops) > 0 && e.ops[len(e.ops)-1].precedence() >= prec {
				if err := e.reduceTop(); err != nil {
					return 0, err
				}
			}
			e.ops = append(e.ops, o)
			expectOperand = true
		default:
			return 0, errCalc
		}
		i++
	}

	if expectOperand {
		return 0, errCalc
	}
	for len(e.ops) > 0 {
		if e.ops[len(e.ops)-1] == opParen {
			return 0, errCalc
		}
		if err := e.reduceTop(); err != nil {
			return 0, err
		}
	}
	return e.values[0], nil
}
