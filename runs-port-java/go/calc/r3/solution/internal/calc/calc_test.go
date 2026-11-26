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
		{"(1 + 2) * 3", 9, nil},
		{"10 - 4 - 3", 3, nil},
		{"1 + 2 * 3 - 4 / 2 % 3", 5, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"--5", 5, nil},
		{"-(2 + 3)", -5, nil},
		{"-2 * 3", -6, nil},
		{"2 * -3", -6, nil},
		{"\t( ( 4 ) )\t", 4, nil},
		{"-9223372036854775807 - 1", -9223372036854775807 - 1, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"3037000499 * 3037000499", 9223372030926249001, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-1 * (-9223372036854775807 - 1)", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"--(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"0 * (9223372036854775807 + 1)", 0, ErrOverflow},
		{"1 / 0", 0, ErrDivideByZero},
		{"5 % 0", 0, ErrDivideByZero},
		{"(1 + 2", 0, ErrSyntax},
		{"1 + 2)", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"", 0, ErrSyntax},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestEvalDeepNesting(t *testing.T) {
	const n = 1_000_000
	in := strings.Repeat("(", n) + "-1" + strings.Repeat(")", n)
	if got, err := Eval([]byte(in)); err != nil || got != -1 {
		t.Fatalf("deep nesting = %d, %v; want -1", got, err)
	}
	in = strings.Repeat("-", n) + "7"
	if got, err := Eval([]byte(in)); err != nil || got != 7 {
		t.Fatalf("long unary chain = %d, %v; want 7", got, err)
	}
}
