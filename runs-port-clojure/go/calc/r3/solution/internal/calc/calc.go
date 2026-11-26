// Package calc evaluates signed 64-bit integer expressions.
//
// Grammar (spaces and tabs may appear between any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
package calc

import (
	"errors"
	"math"
	"math/bits"
)

var (
	// ErrSyntax reports input that does not match the grammar.
	ErrSyntax = errors.New("syntax error")
	// ErrDivByZero reports a division or remainder by zero.
	ErrDivByZero = errors.New("division by zero")
	// ErrOverflow reports a literal or result outside the int64 range.
	ErrOverflow = errors.New("overflow")
)

// IsBlank reports whether line is empty or holds only spaces and tabs.
func IsBlank(line []byte) bool {
	for _, c := range line {
		if !isSpace(c) {
			return false
		}
	}
	return true
}

// Eval evaluates a single expression.
func Eval(line []byte) (int64, error) {
	p := parser{src: line}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	if p.peek() != eof {
		return 0, ErrSyntax
	}
	return v, nil
}

const eof = -1

type parser struct {
	src []byte
	pos int
}

// peek skips blanks and returns the next byte without consuming it, or eof.
func (p *parser) peek() int {
	for p.pos < len(p.src) && isSpace(p.src[p.pos]) {
		p.pos++
	}
	if p.pos >= len(p.src) {
		return eof
	}
	return int(p.src[p.pos])
}

func (p *parser) expr() (int64, error) {
	acc, err := p.term()
	if err != nil {
		return 0, err
	}
	for {
		op := p.peek()
		if op != '+' && op != '-' {
			return acc, nil
		}
		p.pos++
		rhs, err := p.term()
		if err != nil {
			return 0, err
		}
		if acc, err = apply(byte(op), acc, rhs); err != nil {
			return 0, err
		}
	}
}

func (p *parser) term() (int64, error) {
	acc, err := p.unary()
	if err != nil {
		return 0, err
	}
	for {
		op := p.peek()
		if op != '*' && op != '/' && op != '%' {
			return acc, nil
		}
		p.pos++
		rhs, err := p.unary()
		if err != nil {
			return 0, err
		}
		if acc, err = apply(byte(op), acc, rhs); err != nil {
			return 0, err
		}
	}
}

// unary consumes runs of '-' iteratively so long chains do not grow the stack.
func (p *parser) unary() (int64, error) {
	negations := 0
	for p.peek() == '-' {
		p.pos++
		negations++
	}
	v, err := p.primary()
	if err != nil {
		return 0, err
	}
	for ; negations > 0; negations-- {
		if v == math.MinInt64 {
			return 0, ErrOverflow
		}
		v = -v
	}
	return v, nil
}

func (p *parser) primary() (int64, error) {
	switch c := p.peek(); {
	case c == '(':
		p.pos++
		v, err := p.expr()
		if err != nil {
			return 0, err
		}
		if p.peek() != ')' {
			return 0, ErrSyntax
		}
		p.pos++
		return v, nil
	case c >= '0' && c <= '9':
		return p.number()
	default:
		return 0, ErrSyntax
	}
}

func (p *parser) number() (int64, error) {
	var v int64
	overflow := false
	for p.pos < len(p.src) && isDigit(p.src[p.pos]) {
		d := int64(p.src[p.pos] - '0')
		p.pos++
		if overflow {
			continue
		}
		if v > (math.MaxInt64-d)/10 {
			overflow = true
			continue
		}
		v = v*10 + d
	}
	if overflow {
		return 0, ErrOverflow
	}
	return v, nil
}

func apply(op byte, a, b int64) (int64, error) {
	switch op {
	case '+':
		s := a + b
		// Overflow iff both operands share a sign that differs from the sum's.
		if (a^s)&(b^s) < 0 {
			return 0, ErrOverflow
		}
		return s, nil
	case '-':
		d := a - b
		// Overflow iff the operands differ in sign and the result's sign differs from a.
		if (a^b)&(a^d) < 0 {
			return 0, ErrOverflow
		}
		return d, nil
	case '*':
		return mul(a, b)
	case '/':
		if b == 0 {
			return 0, ErrDivByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case '%':
		if b == 0 {
			return 0, ErrDivByZero
		}
		if b == -1 {
			return 0, nil // avoids MinInt64 % -1 trapping on some platforms
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(op))
}

func mul(a, b int64) (int64, error) {
	neg := (a < 0) != (b < 0)
	hi, lo := bits.Mul64(abs(a), abs(b))
	if hi != 0 {
		return 0, ErrOverflow
	}
	if neg {
		if lo > 1<<63 {
			return 0, ErrOverflow
		}
		return int64(-lo), nil
	}
	if lo > math.MaxInt64 {
		return 0, ErrOverflow
	}
	return int64(lo), nil
}

// abs returns |x| as a uint64, which is exact even for math.MinInt64.
func abs(x int64) uint64 {
	if x < 0 {
		return uint64(-x)
	}
	return uint64(x)
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' }
func isDigit(c byte) bool { return c >= '0' && c <= '9' }
