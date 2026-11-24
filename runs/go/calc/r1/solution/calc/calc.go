// Package calc evaluates 64-bit signed integer arithmetic expressions.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Eval.
var (
	ErrSyntax    = errors.New("syntax error")
	ErrDivByZero = errors.New("division by zero")
	ErrOverflow  = errors.New("integer overflow")
)

// Eval parses and evaluates a single expression.
//
// Grammar:
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
func Eval(src []byte) (int64, error) {
	p := parser{src: src}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	p.skipSpace()
	if p.pos != len(p.src) {
		return 0, ErrSyntax
	}
	return v, nil
}

type parser struct {
	src []byte
	pos int
}

func (p *parser) skipSpace() {
	for p.pos < len(p.src) && (p.src[p.pos] == ' ' || p.src[p.pos] == '\t') {
		p.pos++
	}
}

// peek returns the next non-blank byte, or 0 at end of input.
func (p *parser) peek() byte {
	p.skipSpace()
	if p.pos < len(p.src) {
		return p.src[p.pos]
	}
	return 0
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
		default:
			acc, err = rem(acc, rhs)
		}
		if err != nil {
			return 0, err
		}
	}
}

// unary handles chains of '-' iteratively so long chains cannot exhaust the stack.
func (p *parser) unary() (int64, error) {
	negs := 0
	for p.peek() == '-' {
		p.pos++
		negs++
	}
	v, err := p.primary()
	if err != nil {
		return 0, err
	}
	for ; negs > 0; negs-- {
		if v == math.MinInt64 {
			return 0, ErrOverflow
		}
		v = -v
	}
	return v, nil
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
	case isDigit(c):
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

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func add(a, b int64) (int64, error) {
	s := a + b
	if (s > a) != (b > 0) {
		return 0, ErrOverflow
	}
	return s, nil
}

func sub(a, b int64) (int64, error) {
	d := a - b
	if (d < a) != (b > 0) {
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
		return 0, nil
	}
	return a % b, nil
}
