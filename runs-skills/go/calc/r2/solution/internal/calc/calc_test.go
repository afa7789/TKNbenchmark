package calc

import (
	"errors"
	"testing"
)

func TestEval(t *testing.T) {
	t.Parallel()
	tests := []struct {
		in      string
		want    int64
		wantErr error
	}{
		{"1 + 2 * 3", 7, nil},
		{"-7 / 2", -3, nil},
		{"-7 % 3", -1, nil},
		{"7 % -3", 1, nil},
		{"10 - 4 - 3", 3, nil},
		{"--5", 5, nil},
		{"\t( 1 )\t", 1, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"1 / 0", 0, ErrDivByZero},
		{"5 % 0", 0, ErrDivByZero},
		{"(1 + 2", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"1)", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
	}
	for _, tt := range tests {
		t.Run(tt.in, func(t *testing.T) {
			got, err := Eval([]byte(tt.in))
			if !errors.Is(err, tt.wantErr) || (err == nil && got != tt.want) {
				t.Errorf("Eval(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.wantErr)
			}
		})
	}
}
