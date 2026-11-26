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
	errOverflow = errors.New("overflow")
)

// calc evaluates one expression per input line and prints its value or "error".
// Blank lines (only spaces/tabs) produce no output.
func calc(r io.Reader, w *bufio.Writer) error {
	br := bufio.NewReaderSize(r, 1<<20)
	var ev evaluator
	for {
		line, err := readLine(br)
		if err != nil && err != io.EOF {
			return err
		}
		if !isBlank(line) {
			if v, e := ev.eval(line); e != nil {
				w.WriteString("error\n")
			} else {
				w.WriteString(strconv.FormatInt(v, 10))
				w.WriteByte('\n')
			}
		}
		if err == io.EOF {
			return nil
		}
	}
}

func isBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}

// Operator-stack entries. opNeg is unary minus; opParen marks an open '('.
const (
	opParen = '('
	opNeg   = 'n'
)

// precedence returns the binding strength of a stacked operator; '(' never
// pops, so it has the lowest.
func precedence(op byte) int {
	switch op {
	case '+', '-':
		return 1
	case '*', '/', '%':
		return 2
	case opNeg:
		return 3
	}
	return 0
}

// evaluator is an operator-precedence (shunting-yard) evaluator. It uses
// explicit stacks rather than recursion so that deeply nested input cannot
// exhaust the goroutine stack. Its buffers are reused between lines.
type evaluator struct {
	vals []int64
	ops  []byte
}

func (ev *evaluator) eval(s []byte) (int64, error) {
	ev.vals, ev.ops = ev.vals[:0], ev.ops[:0]
	expectOperand := true

	for i := 0; i < len(s); {
		c := s[i]
		switch {
		case c == ' ' || c == '\t':
			i++
		case expectOperand && isDigit(c):
			j := i
			for j < len(s) && isDigit(s[j]) {
				j++
			}
			v, err := parseLiteral(s[i:j])
			if err != nil {
				return 0, err
			}
			ev.vals = append(ev.vals, v)
			expectOperand = false
			i = j
		case expectOperand && c == '-':
			ev.ops = append(ev.ops, opNeg)
			i++
		case expectOperand && c == '(':
			ev.ops = append(ev.ops, opParen)
			i++
		case !expectOperand && (c == '+' || c == '-' || c == '*' || c == '/' || c == '%'):
			if err := ev.reduce(precedence(c)); err != nil {
				return 0, err
			}
			ev.ops = append(ev.ops, c)
			expectOperand = true
			i++
		case !expectOperand && c == ')':
			if err := ev.reduce(1); err != nil {
				return 0, err
			}
			if len(ev.ops) == 0 {
				return 0, errSyntax // unmatched ')'
			}
			ev.ops = ev.ops[:len(ev.ops)-1]
			i++
		default:
			return 0, errSyntax
		}
	}

	if expectOperand {
		return 0, errSyntax // empty input or missing operand
	}
	if err := ev.reduce(1); err != nil {
		return 0, err
	}
	if len(ev.ops) != 0 {
		return 0, errSyntax // unmatched '('
	}
	return ev.vals[0], nil
}

// reduce applies stacked operators while their precedence is at least minPrec.
// All operators are left-associative, so equal precedence also reduces.
func (ev *evaluator) reduce(minPrec int) error {
	for len(ev.ops) > 0 {
		op := ev.ops[len(ev.ops)-1]
		if precedence(op) < minPrec {
			return nil
		}
		ev.ops = ev.ops[:len(ev.ops)-1]

		n := len(ev.vals)
		if op == opNeg {
			v, err := neg(ev.vals[n-1])
			if err != nil {
				return err
			}
			ev.vals[n-1] = v
			continue
		}
		v, err := apply(op, ev.vals[n-2], ev.vals[n-1])
		if err != nil {
			return err
		}
		ev.vals = ev.vals[:n-1]
		ev.vals[n-2] = v
	}
	return nil
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func parseLiteral(digits []byte) (int64, error) {
	var v int64
	for _, d := range digits {
		x := int64(d - '0')
		if v > (math.MaxInt64-x)/10 {
			return 0, errOverflow
		}
		v = v*10 + x
	}
	return v, nil
}

func neg(a int64) (int64, error) {
	if a == math.MinInt64 {
		return 0, errOverflow
	}
	return -a, nil
}

func apply(op byte, a, b int64) (int64, error) {
	switch op {
	case '+':
		r := a + b
		if (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, errOverflow
		}
		return r, nil
	case '-':
		r := a - b
		if (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0) {
			return 0, errOverflow
		}
		return r, nil
	case '*':
		if a == 0 || b == 0 {
			return 0, nil
		}
		r := a * b
		if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || r/b != a {
			return 0, errOverflow
		}
		return r, nil
	case '/':
		if b == 0 {
			return 0, errDivZero
		}
		if a == math.MinInt64 && b == -1 {
			return 0, errOverflow
		}
		return a / b, nil
	case '%':
		if b == 0 {
			return 0, errDivZero
		}
		if b == -1 {
			return 0, nil // avoids the MinInt64 % -1 trap; the result is always 0
		}
		return a % b, nil
	}
	panic("calc: unknown operator " + string(op))
}
