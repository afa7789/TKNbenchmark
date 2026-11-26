package calc

import (
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	tests := []struct {
		expr string
		want int64
		ok   bool
	}{
		{"1 + 2 * 3", 7, true},
		{"-7 / 2", -3, true},
		{"(1 + 2", 0, false},
		{"9223372036854775807 + 1", 0, false},
		{"10 - 4 - 3", 3, true},
		{"1 + 2 * 3 - 4 / 2 % 3", 5, true},
		{"-7 % 3", -1, true},
		{"7 % -3", 1, true},
		{"1 / 0", 0, false},
		{"5 % 0", 0, false},
		{"--5", 5, true},
		{"-(2 + 3)", -5, true},
		{"1 +", 0, false},
		{"()", 0, false},
		{"1 2", 0, false},
		{"+1", 0, false},
		{"1)", 0, false},
		{"9223372036854775808", 0, false},
		{"-9223372036854775807 - 1", -9223372036854775808, true},
		{"(-9223372036854775807 - 1) % -1", 0, true},
		{"(-9223372036854775807 - 1) / -1", 0, false},
		{"(-9223372036854775807 - 1) * -1", 0, false},
		{"-(-9223372036854775807 - 1)", 0, false},
		{"3037000499 * 3037000499", 9223372030926249001, true},
		{"3037000500 * 3037000500", 0, false},
		{"-9223372036854775807 - 2", 0, false},
		{"\t2\t*\t-3 ", -6, true},
	}
	for _, tt := range tests {
		got, ok := Eval(tt.expr)
		if ok != tt.ok || (ok && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.expr, got, ok, tt.want, tt.ok)
		}
	}
}

func TestDeepNesting(t *testing.T) {
	const depth = 1_000_000
	expr := strings.Repeat("(", depth) + "-1" + strings.Repeat(")", depth)
	if got, ok := Eval(expr); !ok || got != -1 {
		t.Fatalf("deep nesting = %d, %v; want -1, true", got, ok)
	}
}
