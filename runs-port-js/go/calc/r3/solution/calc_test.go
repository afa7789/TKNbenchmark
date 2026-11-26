package main

import (
	"bytes"
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
		{"(1 + 2", "error"},
		{"9223372036854775807 + 1", "error"},
		{"-7 % 3", "-1"},
		{"7 % -3", "1"},
		{"1 / 0", "error"},
		{"5 % 0", "error"},
		{"--5", "5"},
		{"10 - 4 - 3", "3"},
		{"(-9223372036854775807 - 1) % -1", "0"},
		{"(-9223372036854775807 - 1) / -1", "error"},
		{"(-9223372036854775807 - 1) * -1", "error"},
		{"-(-9223372036854775807 - 1)", "error"},
		{"-9223372036854775808", "error"},
		{"9223372036854775808", "error"},
		{"009223372036854775807", "9223372036854775807"},
		{"3037000499 * 3037000499", "9223372030926249001"},
		{"3037000500 * 3037000500", "error"},
		{"-9223372036854775807 - 2", "error"},
		{"()", "error"},
		{"1 2", "error"},
		{"+1", "error"},
		{"1)", "error"},
		{"1 +", "error"},
		{"1\r", "error"},
		{strings.Repeat("(", 100000) + "1" + strings.Repeat(")", 100000), "1"},
		{strings.Repeat("-", 100001) + "1", "-1"},
	}
	for _, tt := range tests {
		got := "error"
		if v, err := Evaluate([]byte(tt.in)); err == nil {
			got = strconv.FormatInt(v, 10)
		}
		if got != tt.want {
			t.Errorf("Evaluate(%.40q) = %s, want %s", tt.in, got, tt.want)
		}
	}
}

func TestRun(t *testing.T) {
	in := "\n  42  \n\t\n1+1\nabc\n7"
	var out bytes.Buffer
	if err := run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if want := "42\n2\nerror\n7\n"; out.String() != want {
		t.Errorf("run output %q, want %q", out.String(), want)
	}
}
