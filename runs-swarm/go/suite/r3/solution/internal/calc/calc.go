// Package calc evaluates 64-bit signed integer expressions, one per line.
//
// See the calc section of SPEC.md for the exact input and output formats.
package calc

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"math"
	"strconv"
)

// Errors reported by Eval. Run prints all of them as "error".
var (
	ErrSyntax    = errors.New("syntax error")
	ErrDivByZero = errors.New("division by zero")
	ErrOverflow  = errors.New("integer overflow")
)

// Run reads the whole calc input from r and writes the results to w.
// w is buffered by the caller, which flushes it after Run returns.
func Run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64<<10), math.MaxInt)
	sc.Split(scanLines)
	var buf []byte
	for sc.Scan() {
		line := sc.Bytes()
		if isBlank(line) {
			continue
		}
		v, err := Eval(line)
		switch {
		case err != nil:
			buf = append(buf[:0], "error\n"...)
		default:
			buf = strconv.AppendInt(buf[:0], v, 10)
			buf = append(buf, '\n')
		}
		if _, err := w.Write(buf); err != nil {
			return err
		}
	}
	return sc.Err()
}

// scanLines is like bufio.ScanLines but keeps a trailing '\r', which is not
// part of the grammar and so makes the expression a syntax error.
func scanLines(data []byte, atEOF bool) (advance int, token []byte, err error) {
	if i := bytes.IndexByte(data, '\n'); i >= 0 {
		return i + 1, data[:i], nil
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}

// isBlank reports whether line holds only spaces and tabs.
func isBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Eval evaluates a single expression. It returns ErrSyntax, ErrDivByZero or
// ErrOverflow on failure.
func Eval(line []byte) (int64, error) {
	p := parser{src: line}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	if p.peek() != 0 {
		return 0, ErrSyntax
	}
	return v, nil
}

// parser is a recursive-descent evaluator over one line of input.
type parser struct {
	src []byte
	pos int
}

// peek skips blanks and returns the next byte without consuming it,
// or 0 at end of input.
func (p *parser) peek() byte {
	for p.pos < len(p.src) && (p.src[p.pos] == ' ' || p.src[p.pos] == '\t') {
		p.pos++
	}
	if p.pos == len(p.src) {
		return 0
	}
	return p.src[p.pos]
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
// Chains of '-' are counted iteratively so long runs cannot exhaust the stack.
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
	if negs == 0 {
		return v, nil
	}
	// Only the innermost negation can overflow; later ones operate on a
	// value whose negation is always representable.
	if v == math.MinInt64 {
		return 0, ErrOverflow
	}
	if negs%2 == 1 {
		v = -v
	}
	return v, nil
}

// primary := NUMBER | '(' expr ')'
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

// number parses NUMBER := [0-9]+ at the current position.
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

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

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
		return 0, nil // avoids the MinInt64 % -1 trap; the result is always 0
	}
	return a % b, nil
}
