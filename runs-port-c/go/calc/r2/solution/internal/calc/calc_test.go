package calc

import (
	"errors"
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
		{"\t42 ", 42, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"1 / 0", 0, ErrDivZero},
		{"5 % 0", 0, ErrDivZero},
		{"(1 + 2", 0, ErrSyntax},
		{"1 + 2)", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{strings.Repeat("(", 100000) + "1" + strings.Repeat(")", 100000), 1, nil},
	}
	var ev Evaluator
	for _, tc := range tests {
		got, err := ev.Evaluate([]byte(tc.in))
		name := tc.in
		if len(name) > 40 {
			name = name[:40] + "..."
		}
		if !errors.Is(err, tc.err) || (err == nil && got != tc.want) {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, %v", name, got, err, tc.want, tc.err)
		}
	}
}
