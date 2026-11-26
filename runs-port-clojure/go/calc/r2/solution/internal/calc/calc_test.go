package calc

import (
	"errors"
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		err  error
	}{
		{"1 + 2 * 3", 7, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"10 - 4 - 3", 3, nil},
		{"--5", 5, nil},
		{"2 * -3", -6, nil},
		{"-(2 + 3)", -5, nil},
		{"\t( 1+2 )\t*3 ", 9, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"(1 + 2", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"1\x00", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivideByZero},
		{"5 % 0", 0, ErrDivideByZero},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestDeepNesting(t *testing.T) {
	const n = 100000
	in := strings.Repeat("(", n) + "1" + strings.Repeat(")", n)
	if got, err := Eval([]byte(in)); err != nil || got != 1 {
		t.Fatalf("got %d, %v", got, err)
	}
}
