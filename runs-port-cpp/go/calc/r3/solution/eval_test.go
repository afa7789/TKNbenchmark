package main

import (
	"strconv"
	"strings"
	"testing"
)

func TestEvaluate(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"1 + 2 * 3", "7"},
		{"-7 / 2", "-3"},
		{"-7 % 3", "-1"},
		{"7 % -3", "1"},
		{"10 - 4 - 3", "3"},
		{"--5", "5"},
		{"-(2 + 3)", "-5"},
		{"(1 + 2", "error"},
		{"1 2", "error"},
		{"+1", "error"},
		{"()", "error"},
		{"1)", "error"},
		{"1 / 0", "error"},
		{"5 % 0", "error"},
		{"9223372036854775807", "9223372036854775807"},
		{"9223372036854775808", "error"},
		{"9223372036854775807 + 1", "error"},
		{"-9223372036854775807 - 1", "-9223372036854775808"},
		{"-9223372036854775807 - 2", "error"},
		{"(-9223372036854775807 - 1) % -1", "0"},
		{"(-9223372036854775807 - 1) / -1", "error"},
		{"-(-9223372036854775807 - 1)", "error"},
		{"3037000500 * 3037000500", "error"},
		{"-4294967296 * 2147483648", "-9223372036854775808"},
		{"4294967296 * 2147483648", "error"},
	}
	var ev evaluator
	for _, tt := range tests {
		got := "error"
		if v, ok := ev.evaluate([]byte(tt.in)); ok {
			got = strconv.FormatInt(v, 10)
		}
		if got != tt.want {
			t.Errorf("evaluate(%q) = %s, want %s", tt.in, got, tt.want)
		}
	}
}

func TestRunSkipsBlankLines(t *testing.T) {
	var out strings.Builder
	if err := run(strings.NewReader("\n  42  \n\t\n1+1"), &out); err != nil {
		t.Fatal(err)
	}
	if got, want := out.String(), "42\n2\n"; got != want {
		t.Errorf("run output = %q, want %q", got, want)
	}
}

func TestDeepNesting(t *testing.T) {
	const depth = 1_000_000
	line := strings.Repeat("(", depth) + "1" + strings.Repeat(")", depth)
	var ev evaluator
	if v, ok := ev.evaluate([]byte(line)); !ok || v != 1 {
		t.Errorf("deep nesting = %d, %v; want 1, true", v, ok)
	}
}
