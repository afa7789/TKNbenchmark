// Package calc evaluates signed 64-bit integer arithmetic expressions.
//
// Grammar (spaces and tabs may separate tokens):
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

var (
	// ErrSyntax reports input that does not match the grammar.
	ErrSyntax = errors.New("syntax error")
	// ErrDivByZero reports a division or remainder by zero.
	ErrDivByZero = errors.New("division by zero")
	// ErrOverflow reports a literal or result outside the int64 range.
	ErrOverflow = errors.New("integer overflow")
)

// Eval parses and evaluates the expression in src.
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

// unary handles chains of '-' iteratively so long chains cannot exhaust the stack.
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
	for range negations {
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
	for p.pos < len(p.src) && p.src[p.pos] >= '0' && p.src[p.pos] <= '9' {
		d := int64(p.src[p.pos] - '0')
		if v > (math.MaxInt64-d)/10 {
			overflow = true
		} else {
			v = v*10 + d
		}
		p.pos++
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
		if (b > 0 && s < a) || (b < 0 && s > a) {
			return 0, ErrOverflow
		}
		return s, nil
	case '-':
		d := a - b
		if (b > 0 && d > a) || (b < 0 && d < a) {
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
			return 0, nil
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(op))
}
