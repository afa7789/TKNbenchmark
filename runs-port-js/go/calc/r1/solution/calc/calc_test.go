package calc

import (
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	tests := []struct {
		in   string
		want int64
	}{
		{"1 + 2 * 3", 7},
		{"-7 / 2", -3},
		{"(1 + 2) * 3", 9},
		{"1 + 2 * 3 - 4 / 2 % 3", 5},
		{"10 - 4 - 3", 3},
		{"-7 % 3", -1},
		{"7 % -3", 1},
		{"--5", 5},
		{"2 * -3", -6},
		{"-(2 + 3)", -5},
		{"\t42 ", 42},
		{"-9223372036854775807 - 1", -9223372036854775808},
		{"(-9223372036854775807 - 1) % -1", 0},
		{"3037000499 * 3037000499", 9223372030926249001},
		{strings.Repeat("(", 10000) + "1" + strings.Repeat(")", 10000), 1},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if err != nil || got != tt.want {
			t.Errorf("Eval(%q) = %d, %v; want %d", tt.in, got, err, tt.want)
		}
	}
}

func TestEvalErrors(t *testing.T) {
	for _, in := range []string{
		"(1 + 2", "1 +", "abc", "()", "1 2", "+1", "1)", "1\r", "1(2)",
		"1 / 0", "5 % 0",
		"9223372036854775807 + 1", "-9223372036854775808",
		"(-9223372036854775807 - 1) / -1", "-(-9223372036854775807 - 1)",
		"(-9223372036854775807 - 1) * -1", "3037000500 * 3037000500",
		"-9223372036854775807 - 2",
	} {
		if v, err := Eval([]byte(in)); err == nil {
			t.Errorf("Eval(%q) = %d; want error", in, v)
		}
	}
}
