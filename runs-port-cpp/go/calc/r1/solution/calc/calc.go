// Package calc evaluates 64-bit signed integer arithmetic expressions.
//
// Grammar (spaces and tabs may appear between tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Parsing uses an explicit operator stack (shunting-yard) rather than
// recursion, so arbitrarily deep nesting cannot overflow the call stack.
package calc

import "math"

type op byte

const (
	opAdd op = iota
	opSub
	opMul
	opDiv
	opMod
	opNeg
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

// Evaluator evaluates expressions. Its zero value is ready to use; reusing a
// single Evaluator across calls avoids reallocating its internal stacks.
// An Evaluator is not safe for concurrent use.
type Evaluator struct {
	values []int64
	ops    []op
}

// Eval evaluates a single expression. It reports false on a syntax error,
// division by zero, or 64-bit overflow.
func Eval(expr string) (int64, bool) {
	var e Evaluator
	return e.Evaluate([]byte(expr))
}

// Evaluate returns the value of line, or false on any error.
func (e *Evaluator) Evaluate(line []byte) (int64, bool) {
	e.values = e.values[:0]
	e.ops = e.ops[:0]
	expectOperand := true
	i, n := 0, len(line)

	for {
		for i < n && (line[i] == ' ' || line[i] == '\t') {
			i++
		}
		if i == n {
			break
		}
		c := line[i]

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
			i++
			continue
		}

		if c == ')' {
			for len(e.ops) > 0 && e.top() != opLParen {
				if !e.reduce() {
					return 0, false
				}
			}
			if len(e.ops) == 0 {
				return 0, false
			}
			e.ops = e.ops[:len(e.ops)-1]
		} else if o, ok := binaryOp(c); ok {
			// Left associativity: reduce operators of equal or higher precedence.
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
		i++
	}

	if expectOperand {
		return 0, false
	}
	for len(e.ops) > 0 {
		if e.top() == opLParen || !e.reduce() {
			return 0, false
		}
	}
	return e.values[len(e.values)-1], true
}

func (e *Evaluator) top() op { return e.ops[len(e.ops)-1] }

// reduce applies the operator on top of the stack to its operand(s).
func (e *Evaluator) reduce() bool {
	o := e.top()
	e.ops = e.ops[:len(e.ops)-1]
	last := len(e.values) - 1

	if o == opNeg {
		r, ok := neg(e.values[last])
		e.values[last] = r
		return ok
	}

	rhs, lhs := e.values[last], e.values[last-1]
	e.values = e.values[:last]
	var (
		r  int64
		ok bool
	)
	switch o {
	case opAdd:
		r, ok = add(lhs, rhs)
	case opSub:
		r, ok = sub(lhs, rhs)
	case opMul:
		r, ok = mul(lhs, rhs)
	case opDiv:
		r, ok = div(lhs, rhs)
	case opMod:
		r, ok = mod(lhs, rhs)
	}
	e.values[last-1] = r
	return ok
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// Checked arithmetic: ok is false on overflow or division by zero.

func add(a, b int64) (int64, bool) {
	r := a + b
	return r, (r > a) == (b > 0)
}

func sub(a, b int64) (int64, bool) {
	r := a - b
	return r, (r < a) == (b > 0)
}

func mul(a, b int64) (int64, bool) {
	if a == 0 || b == 0 {
		return 0, true
	}
	r := a * b
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || r/b != a {
		return 0, false
	}
	return r, true
}

func div(a, b int64) (int64, bool) {
	if b == 0 || (a == math.MinInt64 && b == -1) {
		return 0, false
	}
	return a / b, true
}

func mod(a, b int64) (int64, bool) {
	if b == 0 {
		return 0, false
	}
	if b == -1 { // MinInt64 % -1 is 0, not an overflow
		return 0, true
	}
	return a % b, true
}

func neg(a int64) (int64, bool) {
	if a == math.MinInt64 {
		return 0, false
	}
	return -a, true
}
