package main

import (
	"strconv"
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"1 + 2 * 3", "7"},
		{"-7 / 2", "-3"},
		{"(1 + 2", "error"},
		{"9223372036854775807 + 1", "error"},
		{"-7 % 3", "-1"},
		{"7 % -3", "1"},
		{"1 / 0", "error"},
		{"5 % 0", "error"},
		{"--5", "5"},
		{"()", "error"},
		{"1 2", "error"},
		{"+1", "error"},
		{"9223372036854775808", "error"},
		{"-9223372036854775807 - 1", "-9223372036854775808"},
		{"(-9223372036854775807 - 1) % -1", "0"},
		{"(-9223372036854775807 - 1) / -1", "error"},
		{"-(-9223372036854775807 - 1)", "error"},
		{"(-9223372036854775807 - 1) * -1", "error"},
		{"3037000499 * 3037000499", "9223372030926249001"},
		{"3037000500 * 3037000500", "error"},
		{"1)", "error"},
		{"1\r", "error"},
		{strings.Repeat("(", 100000) + "1" + strings.Repeat(")", 100000), "1"},
	}
	var e evaluator
	for _, tt := range tests {
		got := "error"
		if v, err := e.eval([]byte(tt.in)); err == nil {
			got = strconv.FormatInt(v, 10)
		}
		if got != tt.want {
			t.Errorf("eval(%.40q) = %s, want %s", tt.in, got, tt.want)
		}
	}
}

func TestRun(t *testing.T) {
	var out strings.Builder
	if err := run(strings.NewReader("\n  42  \n\t\n1+1"), &out); err != nil {
		t.Fatal(err)
	}
	if got, want := out.String(), "42\n2\n"; got != want {
		t.Errorf("run = %q, want %q", got, want)
	}
}
