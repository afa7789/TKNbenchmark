// Package calc evaluates signed 64-bit integer expressions.
//
// Grammar:
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//
// Any syntax error, division by zero, or overflow makes the whole expression invalid.
package calc

import (
	"errors"
	"math"
)

var (
	// ErrSyntax reports a malformed expression.
	ErrSyntax = errors.New("syntax error")
	// ErrDivByZero reports a division or remainder by zero.
	ErrDivByZero = errors.New("division by zero")
	// ErrOverflow reports a result outside the signed 64-bit range.
	ErrOverflow = errors.New("integer overflow")
)

// Evaluate returns the value of expr, or an error if it is malformed or not representable.
func Evaluate(expr []byte) (int64, error) {
	p := parser{src: expr}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	if p.peek() != eof {
		return 0, ErrSyntax
	}
	return v, nil
}

// IsBlank reports whether line holds only spaces and tabs.
func IsBlank(line []byte) bool {
	for _, b := range line {
		if !isSpace(b) {
			return false
		}
	}
	return true
}

func isSpace(b byte) bool { return b == ' ' || b == '\t' }

func isDigit(b byte) bool { return b >= '0' && b <= '9' }

const eof = -1

type parser struct {
	src []byte
	pos int
}

// peek skips whitespace and returns the next byte without consuming it, or eof.
func (p *parser) peek() int {
	for p.pos < len(p.src) && isSpace(p.src[p.pos]) {
		p.pos++
	}
	if p.pos < len(p.src) {
		return int(p.src[p.pos])
	}
	return eof
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
		if op == '+' {
			acc, err = add(acc, rhs)
		} else {
			acc, err = sub(acc, rhs)
		}
		if err != nil {
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
		switch op {
		case '*':
			acc, err = mul(acc, rhs)
		case '/':
			acc, err = div(acc, rhs)
		case '%':
			acc, err = rem(acc, rhs)
		}
		if err != nil {
			return 0, err
		}
	}
}

func (p *parser) unary() (int64, error) {
	if p.peek() != '-' {
		return p.primary()
	}
	p.pos++
	v, err := p.unary()
	if err != nil {
		return 0, err
	}
	if v == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -v, nil
}

func (p *parser) primary() (int64, error) {
	c := p.peek()
	switch {
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
	for p.pos < len(p.src) && isDigit(p.src[p.pos]) {
		d := int64(p.src[p.pos] - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, ErrOverflow
		}
		v = v*10 + d
		p.pos++
	}
	return v, nil
}

func add(a, b int64) (int64, error) {
	s := a + b
	if (a >= 0) == (b >= 0) && (s >= 0) != (a >= 0) {
		return 0, ErrOverflow
	}
	return s, nil
}

func sub(a, b int64) (int64, error) {
	d := a - b
	if (a >= 0) != (b >= 0) && (d >= 0) != (a >= 0) {
		return 0, ErrOverflow
	}
	return d, nil
}

func mul(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	p := a * b
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || p/b != a {
		return 0, ErrOverflow
	}
	return p, nil
}

func div(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivByZero
	}
	if a == math.MinInt64 && b == -1 {
		return 0, ErrOverflow
	}
	return a / b, nil
}

func rem(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivByZero
	}
	if b == -1 {
		// Avoids the MinInt64 % -1 edge case; the remainder is always 0.
		return 0, nil
	}
	return a % b, nil
}
