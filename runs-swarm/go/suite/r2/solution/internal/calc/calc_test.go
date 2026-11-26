package calc

import (
	"bytes"
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
		{"(1 + 2) * 3", 9, nil},
		{"10 - 4 - 3", 3, nil},
		{"1 + 2 * 3 - 4 / 2 % 3", 5, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"--5", 5, nil},
		{"-(2 + 3)", -5, nil},
		{"2 * -3", -6, nil},
		{"\t007 ", 7, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"(-9223372036854775807 - 1) / 1", -9223372036854775808, nil},
		{"-3037000499 * 3037000499", -9223372030926249001, nil},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"1 / 0", 0, ErrDivByZero},
		{"5 % 0", 0, ErrDivByZero},
		{"", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"(1 + 2", 0, ErrSyntax},
		{"1 + 2)", 0, ErrSyntax},
		{"1 (2)", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"2 ** 3", 0, ErrSyntax},
	}
	for _, tt := range tests {
		got, err := Eval(tt.expr)
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.expr, got, err, tt.want, tt.err)
		}
	}
}

func TestEvalDeepNesting(t *testing.T) {
	const depth = 1_000_000
	expr := strings.Repeat("(", depth) + "-" + strings.Repeat("-", depth) + "1" + strings.Repeat(")", depth)
	got, err := Eval(expr)
	if err != nil || got != -1 {
		t.Fatalf("Eval(deep) = %d, %v; want -1, nil", got, err)
	}
}

func TestRun(t *testing.T) {
	long := strings.Repeat("1+", 100_000) + "1"
	in := "1 + 2 * 3\n-7 / 2\n\n  \t\n(1 + 2\n9223372036854775807 + 1\n" + long + "\n2*3"
	want := "7\n-3\nerror\nerror\n100001\n6\n"
	var out bytes.Buffer
	if err := Run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if out.String() != want {
		t.Errorf("Run output = %q; want %q", out.String(), want)
	}
}
