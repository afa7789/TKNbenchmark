package main

import "math"

// op is an operator held on the evaluator's operator stack.
type op uint8

const (
	opAdd op = iota
	opSub
	opMul
	opDiv
	opRem
	opNeg
	opLParen
)

func (o op) precedence() int {
	switch o {
	case opAdd, opSub:
		return 1
	case opMul, opDiv, opRem:
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
		return opRem, true
	}
	return 0, false
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }
func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// evaluator parses and evaluates expressions using an explicit-stack
// operator-precedence algorithm, so deeply nested input cannot exhaust the
// goroutine stack. Its stacks are reused across calls to avoid allocation.
type evaluator struct {
	values []int64
	ops    []op
}

// evaluate returns the value of line, or ok == false on any syntax or
// arithmetic error.
func (e *evaluator) evaluate(line []byte) (int64, bool) {
	e.values = e.values[:0]
	e.ops = e.ops[:0]

	expectOperand := true
	n := len(line)
	for i := 0; i < n; {
		c := line[i]
		if isBlank(c) {
			i++
			continue
		}
		if expectOperand {
			switch {
			case isDigit(c):
				var v int64
				for ; i < n && isDigit(line[i]); i++ {
					d := int64(line[i] - '0')
					if v > (math.MaxInt64-d)/10 {
						return 0, false
					}
					v = v*10 + d
				}
				e.values = append(e.values, v)
				expectOperand = false
				continue
			case c == '-':
				e.ops = append(e.ops, opNeg)
			case c == '(':
				e.ops = append(e.ops, opLParen)
			default:
				return 0, false
			}
		} else {
			if c == ')' {
				for len(e.ops) > 0 && e.top() != opLParen {
					if !e.reduce() {
						return 0, false
					}
				}
				if len(e.ops) == 0 {
					return 0, false // unbalanced ')'
				}
				e.ops = e.ops[:len(e.ops)-1]
			} else if o, ok := binaryOp(c); ok {
				// All binary operators are left-associative.
				for len(e.ops) > 0 && e.top().precedence() >= o.precedence() {
					if !e.reduce() {
						return 0, false
					}
				}
				e.ops = append(e.ops, o)
				expectOperand = true
			} else {
				return 0, false
			}
		}
		i++
	}

	if expectOperand {
		return 0, false // missing operand (or empty input)
	}
	for len(e.ops) > 0 {
		if e.top() == opLParen {
			return 0, false // unbalanced '('
		}
		if !e.reduce() {
			return 0, false
		}
	}
	if len(e.values) != 1 {
		return 0, false
	}
	return e.values[0], true
}

func (e *evaluator) top() op { return e.ops[len(e.ops)-1] }

// reduce applies the operator on top of the stack to the value stack. It
// reports false on an arithmetic error.
func (e *evaluator) reduce() bool {
	o := e.top()
	e.ops = e.ops[:len(e.ops)-1]

	if o == opNeg {
		last := len(e.values) - 1
		r, ok := checkedNeg(e.values[last])
		e.values[last] = r
		return ok
	}

	last := len(e.values) - 1
	lhs, rhs := e.values[last-1], e.values[last]
	e.values = e.values[:last]

	var r int64
	var ok bool
	switch o {
	case opAdd:
		r, ok = checkedAdd(lhs, rhs)
	case opSub:
		r, ok = checkedSub(lhs, rhs)
	case opMul:
		r, ok = checkedMul(lhs, rhs)
	case opDiv:
		r, ok = checkedDiv(lhs, rhs)
	case opRem:
		r, ok = checkedRem(lhs, rhs)
	}
	e.values[last-1] = r
	return ok
}
