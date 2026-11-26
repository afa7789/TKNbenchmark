package main

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

func TestEvaluate(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		err  error
	}{
		{"1 + 2 * 3", 7, nil},
		{"(1 + 2) * 3", 9, nil},
		{"10 - 4 - 3", 3, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"--5", 5, nil},
		{"\t1\t*\t-2 ", -2, nil},
		{"0009", 9, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"9223372036854775807", 9223372036854775807, nil},

		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},

		{"1 / 0", 0, ErrDivisionByZero},
		{"5 % 0", 0, ErrDivisionByZero},

		{"(1 + 2", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1)", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
	}
	for _, tt := range tests {
		got, err := Evaluate([]byte(tt.in))
		if !errors.Is(err, tt.err) || got != tt.want {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestEvaluateDeepNesting(t *testing.T) {
	const depth = 100000
	in := strings.Repeat("(", depth) + "1" + strings.Repeat(")", depth)
	if got, err := Evaluate([]byte(in)); err != nil || got != 1 {
		t.Fatalf("deep nesting = %d, %v; want 1", got, err)
	}
}

func TestRun(t *testing.T) {
	in := "1 + 2 * 3\n-7 / 2\n\n \t \n(1 + 2\n9223372036854775807 + 1\n" +
		strings.Repeat(" ", 100000) + "42"
	var out bytes.Buffer
	if err := run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	want := "7\n-3\nerror\nerror\n42\n"
	if out.String() != want {
		t.Errorf("run output = %q; want %q", out.String(), want)
	}
}
