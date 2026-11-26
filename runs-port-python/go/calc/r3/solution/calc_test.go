package main

import (
	"strings"
	"testing"
)

func TestEvaluate(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"1 + 2 * 3", 7, true},
		{"-7 / 2", -3, true},
		{"-7 % 3", -1, true},
		{"7 % -3", 1, true},
		{"10 - 4 - 3", 3, true},
		{"--5", 5, true},
		{"-(2 + 3)", -5, true},
		{"9223372036854775807", 9223372036854775807, true},
		{"-9223372036854775807 - 1", -9223372036854775808, true},
		{"(-9223372036854775807 - 1) % -1", 0, true},
		{"0009", 9, true},
		{"9223372036854775808", 0, false},
		{"-9223372036854775808", 0, false},
		{"9223372036854775807 + 1", 0, false},
		{"(-9223372036854775807 - 1) / -1", 0, false},
		{"(-9223372036854775807 - 1) * -1", 0, false},
		{"-(-9223372036854775807 - 1)", 0, false},
		{"3037000500 * 3037000500", 0, false},
		{"1 / 0", 0, false},
		{"5 % 0", 0, false},
		{"(1 + 2", 0, false},
		{"1 + 2)", 0, false},
		{"()", 0, false},
		{"1 2", 0, false},
		{"+1", 0, false},
		{"1 +", 0, false},
		{"1\r", 0, false},
		{"\xb2", 0, false},
	}
	for _, tt := range tests {
		got, err := Evaluate(tt.in)
		if (err == nil) != tt.ok || (tt.ok && got != tt.want) {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, ok=%v", tt.in, got, err, tt.want, tt.ok)
		}
	}
}

func TestEvaluateDeepNesting(t *testing.T) {
	const depth = 1_000_000
	in := strings.Repeat("(", depth) + "1" + strings.Repeat(")", depth)
	if got, err := Evaluate(in); err != nil || got != 1 {
		t.Fatalf("deep nesting = %d, %v", got, err)
	}
}

func TestRun(t *testing.T) {
	var out strings.Builder
	if err := run(strings.NewReader("\n  42  \n\t\n1+1\nx"), &out); err != nil {
		t.Fatal(err)
	}
	if want := "42\n2\nerror\n"; out.String() != want {
		t.Fatalf("run output %q, want %q", out.String(), want)
	}
}
