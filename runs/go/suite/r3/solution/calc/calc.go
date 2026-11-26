// Package calc evaluates 64-bit signed integer arithmetic expressions with
// exact overflow detection.
package calc

import (
	"bufio"
	"errors"
	"io"
	"math"
	"strconv"
)

// Errors reported by Eval.
var (
	ErrSyntax   = errors.New("syntax error")
	ErrDivZero  = errors.New("division by zero")
	ErrOverflow = errors.New("integer overflow")
)

// Eval evaluates a single expression according to the grammar
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//
// Spaces and tabs may separate tokens.
func Eval(s []byte) (int64, error) {
	p := parser{src: s}
	v, err := p.expr()
	if err != nil {
		return 0, err
	}
	if p.peek() != 0 {
		return 0, ErrSyntax
	}
	return v, nil
}

type parser struct {
	src []byte
	pos int
}

// peek skips blanks and returns the next byte, or 0 at end of input.
func (p *parser) peek() byte {
	for p.pos < len(p.src) && (p.src[p.pos] == ' ' || p.src[p.pos] == '\t') {
		p.pos++
	}
	if p.pos == len(p.src) {
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
	negations := 0
	for p.peek() == '-' {
		p.pos++
		negations++
	}
	v, err := p.primary()
	if err != nil {
		return 0, err
	}
	if negations == 0 {
		return v, nil
	}
	if v == math.MinInt64 {
		return 0, ErrOverflow
	}
	if negations%2 == 1 {
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
		return 0, ErrDivZero
	}
	if a == math.MinInt64 && b == -1 {
		return 0, ErrOverflow
	}
	return a / b, nil
}

func rem(a, b int64) (int64, error) {
	if b == 0 {
		return 0, ErrDivZero
	}
	if b == -1 {
		return 0, nil // also covers MinInt64 % -1
	}
	return a % b, nil
}

func isBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Run evaluates each line of r and writes its value, or "error", to w.
// Blank lines (empty or only spaces/tabs) produce no output.
func Run(r io.Reader, w io.Writer) error {
	br := bufio.NewReaderSize(r, 1<<16)
	var out []byte
	for {
		line, err := br.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Overlong line: accumulate it in full.
			full := append([]byte(nil), line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = br.ReadSlice('\n')
				full = append(full, line...)
			}
			line = full
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if n := len(line); n > 0 && line[n-1] == '\n' {
			line = line[:n-1]
		}
		if !isBlank(line) {
			if v, evalErr := Eval(line); evalErr != nil {
				out = append(out, "error"...)
			} else {
				out = strconv.AppendInt(out, v, 10)
			}
			out = append(out, '\n')
			if len(out) >= 1<<15 {
				if _, werr := w.Write(out); werr != nil {
					return werr
				}
				out = out[:0]
			}
		}
		if err != nil { // io.EOF
			break
		}
	}
	_, err := w.Write(out)
	return err
}
