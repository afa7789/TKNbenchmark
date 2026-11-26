package main

import (
	"bufio"
	"errors"
	"io"
	"math"
	"strconv"
)

var (
	errSyntax   = errors.New("syntax error")
	errDivZero  = errors.New("division by zero")
	errOverflow = errors.New("integer overflow")
)

// calc evaluates one expression per line, printing its value or "error".
func calc(r io.Reader, w *bufio.Writer) error {
	return forEachLine(r, func(line []byte) {
		p := parser{src: line}
		p.skipSpace()
		if p.pos == len(p.src) {
			return // blank line
		}
		v, err := p.parse()
		if err != nil {
			w.WriteString("error\n")
			return
		}
		w.WriteString(strconv.FormatInt(v, 10))
		w.WriteByte('\n')
	})
}

// parser is a recursive-descent evaluator over a single line.
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

func (p *parser) parse() (int64, error) {
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	if p.peek() != 0 {
		return 0, errSyntax
	}
	return v, nil
}

// expr := term (('+' | '-') term)*
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

// term := unary (('*' | '/' | '%') unary)*
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

// unary := '-' unary | primary
//
// Leading minus signs are counted iteratively so long runs cannot exhaust
// the stack; they are then applied innermost first, as the grammar implies.
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
		if v, err = neg(v); err != nil {
			return 0, err
		}
	}
	return v, nil
}

// primary := NUMBER | '(' expr ')'
func (p *parser) primary() (int64, error) {
	switch c := p.peek(); {
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
	case '0' <= c && c <= '9':
		return p.number()
	default:
		return 0, errSyntax
	}
}

func (p *parser) number() (int64, error) {
	var v int64
	overflow := false
	for p.pos < len(p.src) && '0' <= p.src[p.pos] && p.src[p.pos] <= '9' {
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

func add(a, b int64) (int64, error) {
	s := a + b
	if (b > 0 && s < a) || (b < 0 && s > a) {
		return 0, errOverflow
	}
	return s, nil
}

func sub(a, b int64) (int64, error) {
	d := a - b
	if (b > 0 && d > a) || (b < 0 && d < a) {
		return 0, errOverflow
	}
	return d, nil
}

func mul(a, b int64) (int64, error) {
	if a == 0 || b == 0 {
		return 0, nil
	}
	p := a * b
	if p/b != a || (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) {
		return 0, errOverflow
	}
	return p, nil
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
		return 0, nil // avoids MinInt64 % -1 edge case; result is always 0
	}
	return a % b, nil
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, errOverflow
	}
	return -a, nil
}
