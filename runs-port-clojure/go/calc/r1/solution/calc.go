package main

import (
	"errors"
	"math"
	"strconv"
)

// Evaluation errors. The CLI reports all of them as "error"; they are kept
// distinct for callers and tests.
var (
	ErrSyntax         = errors.New("syntax error")
	ErrDivisionByZero = errors.New("division by zero")
	ErrOverflow       = errors.New("integer overflow")
)

// Evaluate parses and evaluates a single expression using exact signed
// 64-bit arithmetic. It returns ErrSyntax, ErrDivisionByZero or ErrOverflow
// when the expression is malformed or cannot be computed exactly.
//
// Grammar (spaces and tabs may separate any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
func Evaluate(line []byte) (int64, error) {
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

// eof is returned by peek at the end of input; it is never a valid token.
const eof = 0

// parser is a recursive-descent evaluator working directly on the input
// bytes, so no intermediate token slice is allocated.
type parser struct {
	src []byte
	pos int
}

// peek skips blanks and returns the next byte without consuming it.
func (p *parser) peek() byte {
	for p.pos < len(p.src) && isBlank(p.src[p.pos]) {
		p.pos++
	}
	if p.pos == len(p.src) {
		return eof
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
	if p.peek() != '-' {
		return p.primary()
	}
	p.pos++
	v, err := p.unary()
	if err != nil {
		return 0, err
	}
	return neg(v)
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
	start := p.pos
	for p.pos < len(p.src) && isDigit(p.src[p.pos]) {
		p.pos++
	}
	// The digits are validated above, so the only possible failure is a
	// value out of range.
	v, err := strconv.ParseInt(string(p.src[start:p.pos]), 10, 64)
	if err != nil {
		return 0, ErrOverflow
	}
	return v, nil
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

// IsBlankLine reports whether line holds only spaces and tabs.
func IsBlankLine(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}

// apply computes a op b, reporting overflow and division by zero.
func apply(op byte, a, b int64) (int64, error) {
	switch op {
	case '+':
		s := a + b
		if (a^s)&(b^s) < 0 {
			return 0, ErrOverflow
		}
		return s, nil
	case '-':
		d := a - b
		if (a^b)&(a^d) < 0 {
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
		// Go's % truncates like '/', so the sign follows the dividend.
		// MinInt64 % -1 would trap on some platforms; its value is 0.
		if b == -1 {
			return 0, nil
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + strconv.QuoteRune(rune(op)))
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, ErrOverflow
	}
	return -a, nil
}
