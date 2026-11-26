package calc

import (
	"errors"
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	tests := []struct {
		expr string
		want int64
		err  error
	}{
		{"1 + 2 * 3", 7, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"10 - 4 - 3", 3, nil},
		{"--5", 5, nil},
		{"\t( 1+2 )*3 ", 9, nil},
		{"0009", 9, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"(1 + 2", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1)", 0, ErrSyntax},
		{"2(3)", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivZero},
		{"5 % 0", 0, ErrDivZero},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) - 1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.expr))
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.expr, got, err, tt.want, tt.err)
		}
	}
}

func TestEvalDeepNesting(t *testing.T) {
	const depth = 1_000_000
	expr := strings.Repeat("(", depth) + "-42" + strings.Repeat(")", depth)
	if got, err := Eval([]byte(expr)); err != nil || got != -42 {
		t.Fatalf("deep nesting = %d, %v; want -42", got, err)
	}
}
