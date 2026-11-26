package calc

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"spec example", "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n", "7\n-3\nerror\nerror\n"},
		{"blank lines", "\n  42  \n\t\n1+1", "42\n2\n"},
		{"remainder sign", "-7 % 3\n7 % -3\n", "-1\n1\n"},
		{"division by zero", "1 / 0\n5 % 0\n", "error\nerror\n"},
		{"min int", "-9223372036854775807 - 1\n(-9223372036854775807 - 1) % -1\n", "-9223372036854775808\n0\n"},
		{"literal overflow", "-9223372036854775808\n", "error\n"},
		{"op overflow", "(-9223372036854775807-1) / -1\n(-9223372036854775807-1) * -1\n-(-9223372036854775807-1)\n3037000500*3037000500\n", "error\nerror\nerror\nerror\n"},
		{"unary chains", "--5\n1 - -2\n- - -3\n", "5\n3\n-3\n"},
		{"syntax", "1 +\nabc\n()\n1 2\n+1\n1\r\n", "error\nerror\nerror\nerror\nerror\nerror\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var out strings.Builder
			if err := Run(strings.NewReader(tt.in), &out); err != nil {
				t.Fatalf("Run: %v", err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}
