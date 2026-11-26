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
)

// Errors returned by Eval.
var (
	ErrSyntax       = errors.New("syntax error")
	ErrDivideByZero = errors.New("division by zero")
	ErrOverflow     = errors.New("integer overflow")
)

// Eval parses and evaluates a single expression.
func Eval(s []byte) (int64, error) {
	p := parser{src: s}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	if p.skipSpace(); p.pos != len(p.src) {
		return 0, ErrSyntax
	}
	return v, nil
}

// IsBlank reports whether s holds only spaces and tabs.
func IsBlank(s []byte) bool {
	for _, c := range s {
		if !isSpace(c) {
			return false
		}
	}
	return true
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' }
func isDigit(c byte) bool { return '0' <= c && c <= '9' }

type parser struct {
	src []byte
	pos int
}

func (p *parser) skipSpace() {
	for p.pos < len(p.src) && isSpace(p.src[p.pos]) {
		p.pos++
	}
}

// peek skips whitespace and returns the next byte, or 0 at end of input.
// Callers never treat 0 as a valid token, so a NUL byte in the input is
// still rejected by Eval's end-of-input check.
func (p *parser) peek() byte {
	p.skipSpace()
	if p.pos >= len(p.src) {
		return 0
	}
	return p.src[p.pos]
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
		if acc, err = apply(op, acc, rhs); err != nil {
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
		if acc, err = apply(op, acc, rhs); err != nil {
			return 0, err
		}
	}
}

func (p *parser) unary() (int64, error) {
	// Count consecutive minus signs iteratively so long chains do not recurse.
	neg := 0
	for p.peek() == '-' {
		p.pos++
		neg++
	}
	v, err := p.primary()
	if err != nil {
		return 0, err
	}
	for ; neg > 0; neg-- {
		if v == math.MinInt64 {
			return 0, ErrOverflow
		}
		v = -v
	}
	return v, nil
}

func (p *parser) primary() (int64, error) {
	switch c := p.peek(); {
	case isDigit(c):
		return p.number()
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
		if overflow || v > (math.MaxInt64-d)/10 {
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
		r := a + b
		if (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return r, nil
	case '-':
		r := a - b
		if (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, ErrOverflow
		}
		return r, nil
	case '*':
		if a == 0 || b == 0 {
			return 0, nil
		}
		r := a * b
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || r/b != a {
			return 0, ErrOverflow
		}
		return r, nil
	case '/':
		if b == 0 {
			return 0, ErrDivideByZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, ErrOverflow
		}
		return a / b, nil
	case '%':
		if b == 0 {
			return 0, ErrDivideByZero
		}
		if b == -1 {
			return 0, nil // avoids the MinInt64 % -1 edge case
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(op))
}
