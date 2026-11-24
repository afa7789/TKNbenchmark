package main

import (
	"errors"
	"math"
)

var (
	errSyntax   = errors.New("syntax error")
	errDivZero  = errors.New("division by zero")
	errOverflow = errors.New("integer overflow")
)

// parser is a recursive-descent evaluator over a single expression line.
type parser struct {
	src []byte
	pos int
}

// Eval evaluates one expression according to the calc grammar.
func Eval(src []byte) (int64, error) {
	p := parser{src: src}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	p.skipSpace()
	if p.pos != len(p.src) {
		return 0, errSyntax
	}
	return v, nil
}

func (p *parser) skipSpace() {
	for p.pos < len(p.src) && isSpace(p.src[p.pos]) {
		p.pos++
	}
}

// peek returns the next non-space byte, or 0 at end of input.
func (p *parser) peek() byte {
	p.skipSpace()
	if p.pos < len(p.src) {
		return p.src[p.pos]
	}
	return 0
}

func (p *parser) expr() (int64, error) {
	v, err := p.term()
	if err != nil {
		return 0, err
	}
	for {
		op := p.peek()
		if op != '+' && op != '-' {
			return v, nil
		}
		p.pos++
		rhs, err := p.term()
		if err != nil {
			return 0, err
		}
		if op == '+' {
			v, err = add(v, rhs)
		} else {
			v, err = sub(v, rhs)
		}
		if err != nil {
			return 0, err
		}
	}
}

func (p *parser) term() (int64, error) {
	v, err := p.unary()
	if err != nil {
		return 0, err
	}
	for {
		op := p.peek()
		if op != '*' && op != '/' && op != '%' {
			return v, nil
		}
		p.pos++
		rhs, err := p.unary()
		if err != nil {
			return 0, err
		}
		switch op {
		case '*':
			v, err = mul(v, rhs)
		case '/':
			v, err = div(v, rhs)
		default:
			v, err = rem(v, rhs)
		}
		if err != nil {
			return 0, err
		}
	}
}

func (p *parser) unary() (int64, error) {
	// Count consecutive minus signs iteratively to avoid deep recursion.
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
			return 0, errOverflow
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
			return 0, errSyntax
		}
		p.pos++
		return v, nil
	case isDigit(c):
		return p.number()
	default:
		return 0, errSyntax
	}
}

func (p *parser) number() (int64, error) {
	var v int64
	overflow := false
	for p.pos < len(p.src) && isDigit(p.src[p.pos]) {
		d := int64(p.src[p.pos] - '0')
		if v > (math.MaxInt64-d)/10 {
			overflow = true
		} else {
			v = v*10 + d
		}
		p.pos++
	}
	if overflow {
		return 0, errOverflow
	}
	return v, nil
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' }
func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func add(a, b int64) (int64, error) {
	r := a + b
	if (b > 0 && r < a) || (b < 0 && r > a) {
		return 0, errOverflow
	}
	return r, nil
}

func sub(a, b int64) (int64, error) {
	r := a - b
	if (b > 0 && r > a) || (b < 0 && r < a) {
		return 0, errOverflow
	}
	return r, nil
}

func mul(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	r := a * b
	if r/b != a || (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
		return 0, errOverflow
	}
	return r, nil
}

func div(a, b int64) (int64, error) {
	if b == 0 {
		return 0, errDivZero
	}
	if a == math.MinInt64 && b == -1 {
		return 0, errOverflow
	}
	return a / b, nil
}

func rem(a, b int64) (int64, error) {
	if b == 0 {
		return 0, errDivZero
	}
	if b == -1 {
		return 0, nil
	}
	return a % b, nil
}
