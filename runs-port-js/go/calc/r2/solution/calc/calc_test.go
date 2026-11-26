package calc

import (
	"errors"
	"math"
	"testing"
)

func TestEvaluate(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		err  error
	}{
		{"1 + 2 * 3", 7, nil},
		{"(1 + 2) * 3", 9, nil},
		{"10 - 4 - 3", 3, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"--5", 5, nil},
		{"\t1\t+\t2 ", 3, nil},
		{"0009223372036854775807", math.MaxInt64, nil},
		{"-9223372036854775807 - 1", math.MinInt64, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"", 0, ErrBlank},
		{" \t ", 0, ErrBlank},
		{"(1 + 2", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1)", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivisionByZero},
		{"5 % 0", 0, ErrDivisionByZero},
		{"9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-9223372036854775807 - 2", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
	}
	for _, tt := range tests {
		got, err := Evaluate([]byte(tt.in))
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}
