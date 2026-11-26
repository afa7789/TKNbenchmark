package lru

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"spec example", "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n"},
		{"overwrite refreshes", "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c\n", "9\nNULL\n3\n"},
		{"del and size", "3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n"},
		{"capacity one", "1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n"},
		{"no trailing newline", "2\nSET a 1\nGET a", "1\n"},
		{"slot reuse after delete", "2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\nNULL\n3\n4\n2\n"},
		{"get refreshes", "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\n", "1\n1\nNULL\n"},
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

func TestRunInvalidCapacity(t *testing.T) {
	for _, in := range []string{"", "0\n", "x\n", "1000001\n"} {
		var out strings.Builder
		if err := Run(strings.NewReader(in), &out); err == nil {
			t.Errorf("Run(%q): expected error", in)
		}
	}
}
