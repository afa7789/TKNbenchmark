package main

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct{ in, want string }{
		{"The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"", ""},
		{"123 _ '", ""},
		{"don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"caf\xc3\xa9 CAF\xff", "2 caf\n"},
	}
	for _, tt := range tests {
		var sb strings.Builder
		if err := run(strings.NewReader(tt.in), &sb); err != nil {
			t.Fatalf("run(%q): %v", tt.in, err)
		}
		if got := sb.String(); got != tt.want {
			t.Errorf("run(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}
