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
		{"\t( 1 )\t", 1, nil},
		{"(-9223372036854775807 - 1) % -1", 0, nil},
		{"-9223372036854775807 - 1", -9223372036854775808, nil},
		{"9223372036854775807", 9223372036854775807, nil},
		{"(1 + 2", 0, ErrSyntax},
		{"1 +", 0, ErrSyntax},
		{"()", 0, ErrSyntax},
		{"1 2", 0, ErrSyntax},
		{"+1", 0, ErrSyntax},
		{"1)", 0, ErrSyntax},
		{"abc", 0, ErrSyntax},
		{"1\r", 0, ErrSyntax},
		{"1 / 0", 0, ErrDivByZero},
		{"5 % 0", 0, ErrDivByZero},
		{"9223372036854775807 + 1", 0, ErrOverflow},
		{"9223372036854775808", 0, ErrOverflow},
		{"-9223372036854775808", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) / -1", 0, ErrOverflow},
		{"(-9223372036854775807 - 1) * -1", 0, ErrOverflow},
		{"-(-9223372036854775807 - 1)", 0, ErrOverflow},
		{"3037000500 * 3037000500", 0, ErrOverflow},
		{"3037000499 * 3037000499", 9223372030926249001, nil},
	}
	for _, tt := range tests {
		got, err := Evaluate([]byte(tt.in))
		if !errors.Is(err, tt.err) || (err == nil && got != tt.want) {
			t.Errorf("Evaluate(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestDeepNesting(t *testing.T) {
	const depth = 1_000_000
	src := strings.Repeat("(", depth) + "42" + strings.Repeat(")", depth)
	if got, err := Evaluate([]byte(src)); err != nil || got != 42 {
		t.Fatalf("got %d, %v", got, err)
	}
	src = strings.Repeat("-", depth+1) + "1"
	if got, err := Evaluate([]byte(src)); err != nil || got != -1 {
		t.Fatalf("got %d, %v; want -1", got, err)
	}
}

func TestParseNumber(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		err  error
	}{
		{"0", 0, nil},
		{"00009223372036854775807", 9223372036854775807, nil},
		{"9223372036854775806", 9223372036854775806, nil},
		{"9223372036854775808", 0, ErrOverflow},
		{"99999999999999999999", 0, ErrOverflow},
	}
	for _, tt := range tests {
		got, err := parseNumber([]byte(tt.in))
		if !errors.Is(err, tt.err) || got != tt.want {
			t.Errorf("parseNumber(%q) = %d, %v; want %d, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}
