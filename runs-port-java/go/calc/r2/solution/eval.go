package main

import (
	"errors"
	"math"
)

// Errors reported by Evaluate. The program only prints "error", but distinct
// values keep the evaluator testable and self-describing.
var (
	ErrSyntax         = errors.New("syntax error")
	ErrDivisionByZero = errors.New("division by zero")
	ErrOverflow       = errors.New("overflow")
)

// level holds the partial state of one parenthesis nesting level:
//
//	expr  := term  (('+' | '-') term)*
//	term  := unary (('*' | '/' | '%') unary)*
//	unary := '-' unary | primary
//
// sum is the value of the terms seen so far and addOp the operator that joins
// it to the current term (0 before the first term). prod and mulOp do the same
// for the factors of the current term. neg counts pending unary minuses for
// the operand being parsed.
type level struct {
	sum   int64
	addOp byte
	prod  int64
	mulOp byte
	neg   int
}

// Evaluate parses and evaluates src as a complete expression of 64-bit signed
// integers. Spaces and tabs may appear between tokens.
//
// Parsing uses an explicit stack instead of recursion, so arbitrarily deep
// nesting cannot exhaust the goroutine stack.
func Evaluate(src []byte) (int64, error) {
	p := parser{src: src}
	var stack []level
	cur := level{}

	for {
		// Operand: any number of '-', then a number or '('.
		c := p.peek()
		for c == '-' {
			p.pos++
			cur.neg++
			c = p.peek()
		}
		if c == '(' {
			p.pos++
			stack = append(stack, cur)
			cur = level{}
			continue
		}
		if !isDigit(c) {
			return 0, ErrSyntax
		}
		value, err := p.number()
		if err != nil {
			return 0, err
		}

		// Close as many levels as the operand completes, then continue with
		// the next binary operator.
		for {
			if value, err = negate(value, cur.neg); err != nil {
				return 0, err
			}
			cur.neg = 0
			if cur.mulOp != 0 {
				if value, err = apply(cur.mulOp, cur.prod, value); err != nil {
					return 0, err
				}
			}
			cur.prod, cur.mulOp = value, 0

			c = p.peek()
			if c == '*' || c == '/' || c == '%' {
				p.pos++
				cur.mulOp = c
				break
			}

			// The term is complete; fold it into the sum.
			if cur.addOp != 0 {
				if value, err = apply(cur.addOp, cur.sum, cur.prod); err != nil {
					return 0, err
				}
			}
			cur.sum, cur.addOp = value, 0

			switch {
			case c == '+' || c == '-':
				p.pos++
				cur.addOp = c
			case c == ')' && len(stack) > 0:
				p.pos++
				cur = stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				continue // value is now an operand of the enclosing level
			case p.atEnd() && len(stack) == 0:
				return cur.sum, nil
			default:
				return 0, ErrSyntax
			}
			break
		}
	}
}

// parser is a cursor over one input line.
type parser struct {
	src []byte
	pos int
}

// peek skips blanks and returns the next byte without consuming it, or 0 at
// end of input. A NUL byte in the input is never valid, so callers that need
// to distinguish it use atEnd.
func (p *parser) peek() byte {
	for p.pos < len(p.src) && isBlank(p.src[p.pos]) {
		p.pos++
	}
	if p.pos < len(p.src) {
		return p.src[p.pos]
	}
	return 0
}

func (p *parser) atEnd() bool {
	return p.pos >= len(p.src)
}

// number consumes a run of digits. Literals above math.MaxInt64 overflow.
func (p *parser) number() (int64, error) {
	var value int64
	overflow := false
	for p.pos < len(p.src) && isDigit(p.src[p.pos]) {
		digit := int64(p.src[p.pos] - '0')
		p.pos++
		if value > (math.MaxInt64-digit)/10 {
			overflow = true
		} else if !overflow {
			value = value*10 + digit
		}
	}
	if overflow {
		return 0, ErrOverflow
	}
	return value, nil
}

// negate applies n unary minuses to v.
func negate(v int64, n int) (int64, error) {
	for ; n > 0; n-- {
		if v == math.MinInt64 {
			return 0, ErrOverflow
		}
		v = -v
	}
	return v, nil
}

// apply evaluates a binary operator, reporting overflow of the exact result
// and division by zero.
func apply(op byte, a, b int64) (int64, error) {
	switch op {
	case '+':
		s := a + b
		if (a >= 0) == (b >= 0) && (s >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return s, nil
	case '-':
		d := a - b
		if (a >= 0) != (b >= 0) && (d >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return d, nil
	case '*':
		if a == 0 || b == 0 {
			return 0, nil
		}
		m := a * b
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || m/b != a {
			return 0, ErrOverflow
		}
		return m, nil
	case '/':
		if b == 0 {
			return 0, ErrDivisionByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case '%':
		if b == 0 {
			return 0, ErrDivisionByZero
		}
		if b == -1 {
			return 0, nil // avoids MinInt64 % -1 trapping on some platforms
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(op))
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
