package main

import (
	"math"
	"math/bits"
)

// op is an operator held on the evaluator's operator stack.
type op byte

const (
	opNeg op = iota
	opAdd
	opSub
	opMul
	opDiv
	opMod
	opLParen
)

func (o op) precedence() int {
	switch o {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opMod:
		return 2
	case opNeg:
		return 3
	default: // opLParen
		return 0
	}
}

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

func negate(a int64) (int64, bool) {
	if a == math.MinInt64 {
		return 0, false
	}
	return -a, true
}

func mulChecked(a, b int64) (int64, bool) {
	neg := (a < 0) != (b < 0)
	hi, lo := bits.Mul64(absU64(a), absU64(b))
	if hi != 0 {
		return 0, false
	}
	if neg {
		if lo > 1<<63 {
			return 0, false
		}
		return int64(-lo), true
	}
	if lo > math.MaxInt64 {
		return 0, false
	}
	return int64(lo), true
}

func absU64(a int64) uint64 {
	if a < 0 {
		return -uint64(a)
	}
	return uint64(a)
}

// apply evaluates a binary operator, reporting false on overflow or division by zero.
func apply(o op, a, b int64) (int64, bool) {
	switch o {
	case opAdd:
		r := a + b
		if (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, false
		}
		return r, true
	case opSub:
		r := a - b
		if (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, false
		}
		return r, true
	case opMul:
		return mulChecked(a, b)
	case opDiv:
		if b == 0 || (a == math.MinInt64 && b == -1) {
			return 0, false
		}
		return a / b, true
	case opMod:
		if b == 0 {
			return 0, false
		}
		return a % b, true // Go defines MinInt64 % -1 == 0.
	}
	return 0, false
}

// evaluator is an iterative operator-precedence parser, so arbitrarily deep
// nesting cannot overflow the call stack. Its stacks are reused across lines.
type evaluator struct {
	values []int64
	ops    []op
}

// evaluate returns the value of line, or false on any syntax or arithmetic error.
func (e *evaluator) evaluate(line []byte) (int64, bool) {
	e.values = e.values[:0]
	e.ops = e.ops[:0]

	expectOperand := true
	n := len(line)
	for i := 0; ; {
		for i < n && isBlank(line[i]) {
			i++
		}
		if i == n {
			break
		}
		c := line[i]

		if expectOperand {
			switch {
			case c == '-':
				e.ops = append(e.ops, opNeg)
				i++
			case c == '(':
				e.ops = append(e.ops, opLParen)
				i++
			case isDigit(c):
				v, next, ok := parseNumber(line, i)
				if !ok {
					return 0, false
				}
				e.values = append(e.values, v)
				i = next
				expectOperand = false
			default:
				return 0, false
			}
			continue
		}

		if c == ')' {
			if !e.reduceUntilParen() || len(e.ops) == 0 {
				return 0, false // arithmetic error or unmatched ')'
			}
			e.ops = e.ops[:len(e.ops)-1]
			i++
			continue
		}
		o, ok := binaryOp(c)
		if !ok {
			return 0, false
		}
		p := o.precedence()
		for len(e.ops) > 0 && e.ops[len(e.ops)-1].precedence() >= p {
			if !e.reduceOnce() {
				return 0, false
			}
		}
		e.ops = append(e.ops, o)
		expectOperand = true
		i++
	}

	if expectOperand || !e.reduceUntilParen() {
		return 0, false
	}
	if len(e.ops) != 0 || len(e.values) != 1 {
		return 0, false // unmatched '('
	}
	return e.values[0], true
}

// parseNumber parses the digits starting at line[i], returning the value and
// the index just past them; it reports false if the literal exceeds MaxInt64.
func parseNumber(line []byte, i int) (int64, int, bool) {
	var v int64
	overflow := false
	for ; i < len(line) && isDigit(line[i]); i++ {
		d := int64(line[i] - '0')
		if v > (math.MaxInt64-d)/10 {
			overflow = true
		} else if !overflow {
			v = v*10 + d
		}
	}
	return v, i, !overflow
}

// reduceUntilParen applies operators until the stack is empty or its top is '('.
func (e *evaluator) reduceUntilParen() bool {
	for len(e.ops) > 0 && e.ops[len(e.ops)-1] != opLParen {
		if !e.reduceOnce() {
			return false
		}
	}
	return true
}

// reduceOnce pops the top operator and applies it to the value stack.
func (e *evaluator) reduceOnce() bool {
	o := e.ops[len(e.ops)-1]
	e.ops = e.ops[:len(e.ops)-1]

	var (
		r  int64
		ok bool
	)
	top := len(e.values) - 1
	if o == opNeg {
		r, ok = negate(e.values[top])
		e.values = e.values[:top]
	} else {
		a, b := e.values[top-1], e.values[top]
		r, ok = apply(o, a, b)
		e.values = e.values[:top-1]
	}
	if !ok {
		return false
	}
	e.values = append(e.values, r)
	return true
}
