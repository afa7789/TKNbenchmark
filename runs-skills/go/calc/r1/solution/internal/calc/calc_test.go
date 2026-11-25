package calc

import (
	"errors"
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	t.Parallel()
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
		{"\t( 1+2 )\t*3 ", 9, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"(1 + 2", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivByZero},
		{"1 % 0", 0, ErrDivByZero},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"3037000499 * 3037000499", 9223372030926249001, nil},
		{strings.Repeat("(", 10000) + "1" + strings.Repeat(")", 10000), 1, nil},
		{strings.Repeat("-", 10001) + "1", -1, nil},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if !errors.Is(err, tt.err) || got != tt.want {
			t.Errorf("Eval(%.40q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}
