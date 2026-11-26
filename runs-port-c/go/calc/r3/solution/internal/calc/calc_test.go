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
		{"(1 + 2", 0, ErrSyntax},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"10 - 4 - 3", 3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"1 / 0", 0, ErrDivideByZero},
		{"5 % 0", 0, ErrDivideByZero},
		{"--5", 5, nil},
		{"-(2 + 3)", -5, nil},
		{"1 - -2", 3, nil},
		{"+1", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1)", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775807 - 1", -9223372036854775807 - 1, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000499 * 3037000499", 9223372030926249001, nil},
		{"4294967296 * 4294967296", 0, ErrOverflow},
		{strings.Repeat("(", 100000) + "1" + strings.Repeat(")", 100000), 1, nil},
	}
	var ev Evaluator
	for _, tt := range tests {
		name := tt.expr
		if len(name) > 40 {
			name = name[:40]
		}
		got, err := ev.Evaluate([]byte(tt.expr))
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, %v", name, got, err, tt.want, tt.err)
		}
	}
}
