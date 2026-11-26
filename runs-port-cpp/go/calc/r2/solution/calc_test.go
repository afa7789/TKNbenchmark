package main

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"spec", "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n", "7\n-3\nerror\nerror\n"},
		{"rem sign", "-7 % 3\n7 % -3\n", "-1\n1\n"},
		{"min rem", "(-9223372036854775807 - 1) % -1\n", "0\n"},
		{"min div", "(-9223372036854775807 - 1) / -1\n", "error\n"},
		{"min neg", "-(-9223372036854775807 - 1)\n", "error\n"},
		{"min literal", "-9223372036854775808\n", "error\n"},
		{"mul overflow", "3037000500 * 3037000500\n-3037000499 * 3037000499\n", "error\n-9223372030926249001\n"},
		{"min mul", "(-9223372036854775807 - 1) * 1\n(-9223372036854775807-1) * -1\n", "-9223372036854775808\nerror\n"},
		{"blank", "\n \t \n5", "5\n"},
		{"syntax", "1 +\nabc\n()\n1 2\n+1\n)\n1)\n", "error\nerror\nerror\nerror\nerror\nerror\nerror\n"},
		{"unary", "--5\n2*-3\n1 - -2\n-(2+3)\n", "5\n-6\n3\n-5\n"},
		{"deep", strings.Repeat("(", 100000) + "1" + strings.Repeat(")", 100000) + "\n", "1\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var sb strings.Builder
			if err := run(strings.NewReader(tt.in), &sb); err != nil {
				t.Fatal(err)
			}
			if got := sb.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}
