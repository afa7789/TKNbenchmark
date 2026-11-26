// Package calc evaluates signed 64-bit integer expressions with exact,
// overflow-checked arithmetic.
//
// Grammar (spaces and tabs may appear between any two tokens):
//
//	expr    := term    (('+' | '-') term)*
//	term    := unary   (('*' | '/' | '%') unary)*
//	unary   := '-' unary | primary
//	primary := NUMBER | '(' expr ')'
//	NUMBER  := [0-9]+
//
// Operators are left-associative. The evaluator is iterative, keeping one
// frame per open parenthesis on the heap, so nesting depth is limited only by
// available memory.
package calc

import (
	"errors"
	"math"
)

// Errors reported by Eval.
var (
	ErrSyntax       = errors.New("syntax error")
	ErrDivideByZero = errors.New("division by zero")
	ErrOverflow     = errors.New("integer overflow")
)

// frame holds the partial state of one expr: the running sum of completed
// terms, the running product of the current term, and the unary minuses that
// precede the operand being parsed.
type frame struct {
	sum   int64
	addOp byte // operator joining sum and the current term; 0 if none yet
	prod  int64
	mulOp byte // operator joining prod and the next operand; 0 if none yet
	negs  int  // unary minuses applied to the pending operand
}

// pushOperand folds a fully parsed primary into the current term.
func (f *frame) pushOperand(v int64) error {
	if f.negs > 0 {
		// Only the innermost negation can overflow; after it the value is
		// never MinInt64, so the rest just flip the sign.
		if v == math.MinInt64 {
			return ErrOverflow
		}
		if f.negs%2 == 1 {
			v = -v
		}
		f.negs = 0
	}
	if f.mulOp == 0 {
		f.prod = v
		return nil
	}
	var err error
	f.prod, err = apply(f.mulOp, f.prod, v)
	f.mulOp = 0
	return err
}

// endTerm folds the current term into the sum.
func (f *frame) endTerm() error {
	if f.addOp == 0 {
		f.sum = f.prod
		return nil
	}
	var err error
	f.sum, err = apply(f.addOp, f.sum, f.prod)
	f.addOp = 0
	return err
}

// Eval evaluates a complete expression.
func Eval(src []byte) (int64, error) {
	s := scanner{src: src}
	var stack []frame // enclosing frames, one per open parenthesis
	cur := frame{}

	for {
		// Operand position: unary minuses, then a number or '('.
		for s.peek() == '-' {
			s.pos++
			cur.negs++
		}
		switch c := s.peek(); {
		case c == '(':
			s.pos++
			stack = append(stack, cur)
			cur = frame{}
			continue
		case isDigit(c):
			v, err := s.number()
			if err != nil {
				return 0, err
			}
			if err := cur.pushOperand(v); err != nil {
				return 0, err
			}
		default:
			return 0, ErrSyntax
		}

		// Operator position: close as many parentheses as follow, then expect
		// a binary operator or the end of input.
		for {
			c := s.peek()
			switch c {
			case '*', '/', '%':
				s.pos++
				cur.mulOp = byte(c)
			case '+', '-':
				s.pos++
				if err := cur.endTerm(); err != nil {
					return 0, err
				}
				cur.addOp = byte(c)
			case ')':
				if len(stack) == 0 {
					return 0, ErrSyntax
				}
				s.pos++
				if err := cur.endTerm(); err != nil {
					return 0, err
				}
				v := cur.sum
				cur = stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				if err := cur.pushOperand(v); err != nil {
					return 0, err
				}
				continue
			case -1:
				if len(stack) != 0 {
					return 0, ErrSyntax
				}
				if err := cur.endTerm(); err != nil {
					return 0, err
				}
				return cur.sum, nil
			default:
				return 0, ErrSyntax
			}
			break
		}
	}
}

type scanner struct {
	src []byte
	pos int
}

// peek skips blanks and returns the next byte without consuming it, or -1 at
// end of input.
func (s *scanner) peek() int {
	for s.pos < len(s.src) && (s.src[s.pos] == ' ' || s.src[s.pos] == '\t') {
		s.pos++
	}
	if s.pos == len(s.src) {
		return -1
	}
	return int(s.src[s.pos])
}

// number consumes a run of decimal digits.
func (s *scanner) number() (int64, error) {
	var v int64
	for s.pos < len(s.src) && isDigit(int(s.src[s.pos])) {
		d := int64(s.src[s.pos] - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, ErrOverflow
		}
		v = v*10 + d
		s.pos++
	}
	return v, nil
}

func isDigit(c int) bool { return c >= '0' && c <= '9' }

// apply computes left op right exactly, reporting overflow and division by zero.
func apply(op byte, left, right int64) (int64, error) {
	switch op {
	case '+':
		r := left + right
		if (left^r)&(right^r) < 0 {
			return 0, ErrOverflow
		}
		return r, nil
	case '-':
		r := left - right
		if (left^right)&(left^r) < 0 {
			return 0, ErrOverflow
		}
		return r, nil
	case '*':
		if left == 0 || right == 0 {
			return 0, nil
		}
		r := left * right
		if r/right != left || (left == math.MinInt64 && right == -1) {
			return 0, ErrOverflow
		}
		return r, nil
	case '/':
		if right == 0 {
			return 0, ErrDivideByZero
		}
		if left == math.MinInt64 && right == -1 {
			return 0, ErrOverflow
		}
		return left / right, nil
	case '%':
		if right == 0 {
			return 0, ErrDivideByZero
		}
		// MinInt64 % -1 is 0 in Go, which is the required result.
		return left % right, nil
	default:
		panic("calc: unknown operator " + string(op))
	}
}
