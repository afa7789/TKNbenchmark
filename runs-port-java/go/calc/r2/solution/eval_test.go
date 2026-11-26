package main

import (
	"bytes"
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
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"10 - 4 - 3", 3, nil},
		{"--5", 5, nil},
		{"-(2 + 3)", -5, nil},
		{"\t( 1 )\t", 1, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"00012", 12, nil},
		{"(1 + 2", 0, ErrSyntax},
		{"1 + 2)", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"5\xff", 0, ErrSyntax},
		{"5\x00", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivisionByZero},
		{"5 % 0", 0, ErrDivisionByZero},
		{"9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-1 * (-9223372036854775807 - 1)", 0, ErrOverflow},
	}
	for _, tt := range tests {
		got, err := Evaluate([]byte(tt.in))
		if err != tt.err || got != tt.want {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestDeepNesting(t *testing.T) {
	const n = 1_000_000
	src := strings.Repeat("(", n) + "-1" + strings.Repeat(")", n)
	if got, err := Evaluate([]byte(src)); err != nil || got != -1 {
		t.Fatalf("got %d, %v", got, err)
	}
	if _, err := Evaluate([]byte(src[:len(src)-1])); err != ErrSyntax {
		t.Fatalf("unbalanced: got %v", err)
	}
}

func TestRun(t *testing.T) {
	in := "1 + 2 * 3\n\n  \t\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n42"
	var out bytes.Buffer
	if err := run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if want := "7\n-3\nerror\nerror\n42\n"; out.String() != want {
		t.Fatalf("got %q, want %q", out.String(), want)
	}
}
