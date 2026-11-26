package calc

import (
	"errors"
	"strings"
	"testing"
)

func TestEvaluate(t *testing.T) {
	tests := []struct {
		expr string
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
		{"\t2*(3+4)*5 ", 70, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"(1 + 2", 0, ErrSyntax},
		{"1 + 2)", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivByZero},
		{"5 % 0", 0, ErrDivByZero},
		{"9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"3037000499 * 3037000499", 9223372030926249001, nil},
		{strings.Repeat("(", 100000) + "1" + strings.Repeat(")", 100000), 1, nil},
	}
	var ev Evaluator
	for _, tt := range tests {
		got, err := ev.Evaluate([]byte(tt.expr))
		name := tt.expr
		if len(name) > 40 {
			name = name[:40] + "..."
		}
		if !errors.Is(err, tt.err) {
			t.Errorf("Evaluate(%q) error = %v, want %v", name, err, tt.err)
			continue
		}
		if err == nil && got != tt.want {
			t.Errorf("Evaluate(%q) = %d, want %d", name, got, tt.want)
		}
	}
}
