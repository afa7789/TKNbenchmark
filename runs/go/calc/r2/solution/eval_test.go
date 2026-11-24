package main

import (
	"bytes"
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
		{"- - 5", 5, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-1 * (-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"3037000499 * 3037000499", 9223372030926249001, nil},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"1 / 0", 0, ErrDivByZero},
		{"5 % 0", 0, ErrDivByZero},
		{"(1 + 2", 0, ErrSyntax},
		{"1 + 2)", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"\t(\t1\t)\t", 1, nil},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if err != tt.err || (err == nil && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestRun(t *testing.T) {
	in := "1 + 2 * 3\n\n  \t\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n42"
	var out bytes.Buffer
	if err := run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if want := "7\n-3\nerror\nerror\n42\n"; out.String() != want {
		t.Errorf("got %q, want %q", out.String(), want)
	}
}
