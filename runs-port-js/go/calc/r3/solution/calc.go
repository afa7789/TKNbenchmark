package main

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
	opLParen op = iota
	opNeg
	opAdd
	opSub
	opMul
	opDiv
	opMod
)

// prec returns the binding strength of o; opLParen binds weakest so that it
// is never reduced by an operator.
func (o op) prec() int {
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

// binaryOp maps an operator character to its op.
func binaryOp(c byte) (op, bool) {
	switch c {
	case '+':
		return opAdd, true
	case '-':
		return opSub, true
	case '*':
		return opMul, true
	case '/':
		return opDiv, true
	case '%':
		return opMod, true
	}
	return 0, false
}

// evaluator holds the operand and operator stacks of a shunting-yard parse.
// The parse is iterative so arbitrarily deep nesting cannot exhaust the
// call stack.
type evaluator struct {
	values []int64
	ops    []op
}

// reduce pops the top operator and applies it to the operand stack.
func (e *evaluator) reduce() error {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]
	if o == opNeg {
		top := &e.values[len(e.values)-1]
		if *top == math.MinInt64 {
			return ErrOverflow
		}
		*top = -*top
		return nil
	}
	n := len(e.values)
	v, err := apply(o, e.values[n-2], e.values[n-1])
	if err != nil {
		return err
	}
	e.values[n-2] = v
	e.values = e.values[:n-1]
	return nil
}

// apply computes a o b, reporting overflow and division by zero.
func apply(o op, a, b int64) (int64, error) {
	switch o {
	case opAdd:
		s := a + b
		if (a^s)&(b^s) < 0 {
			return 0, ErrOverflow
		}
		return s, nil
	case opSub:
		d := a - b
		if (a^b)&(a^d) < 0 {
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
			return 0, ErrDivideByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case opMod:
		if b == 0 {
			return 0, ErrDivideByZero
		}
		if b == -1 {
			return 0, nil
		}
		return a % b, nil
	}
	return 0, ErrSyntax
}

// Evaluate parses and evaluates one expression using 64-bit signed integer
// arithmetic.
func Evaluate(line []byte) (int64, error) {
	e := evaluator{
		values: make([]int64, 0, 16),
		ops:    make([]op, 0, 16),
	}
	expectOperand := true
	for i := 0; i < len(line); i++ {
		c := line[i]
		if c == ' ' || c == '\t' {
			continue
		}
		if expectOperand {
			switch {
			case isDigit(c):
				var v int64
				for ; i < len(line) && isDigit(line[i]); i++ {
					d := int64(line[i] - '0')
					if v > (math.MaxInt64-d)/10 {
						return 0, ErrOverflow
					}
					v = v*10 + d
				}
				i--
				e.values = append(e.values, v)
				expectOperand = false
			case c == '-':
				e.ops = append(e.ops, opNeg)
			case c == '(':
				e.ops = append(e.ops, opLParen)
			default:
				return 0, ErrSyntax
			}
			continue
		}
		if c == ')' {
			for len(e.ops) > 0 && e.ops[len(e.ops)-1] != opLParen {
				if err := e.reduce(); err != nil {
					return 0, err
				}
			}
			if len(e.ops) == 0 {
				return 0, ErrSyntax
			}
			e.ops = e.ops[:len(e.ops)-1]
			continue
		}
		o, ok := binaryOp(c)
		if !ok {
			return 0, ErrSyntax
		}
		for len(e.ops) > 0 && e.ops[len(e.ops)-1].prec() >= o.prec() {
			if err := e.reduce(); err != nil {
				return 0, err
			}
		}
		e.ops = append(e.ops, o)
		expectOperand = true
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

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
