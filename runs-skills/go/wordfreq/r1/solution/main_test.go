package main

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, in, want string
	}{
		{"simple", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"empty", "", ""},
		{"separators", "don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"high bytes", "caf\xc3\xa9 caf\xffx", "2 caf\n1 x\n"},
		{"trailing word", "a b a", "2 a\n1 b\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			var out strings.Builder
			if err := run(strings.NewReader(tt.in), &out); err != nil {
				t.Fatal(err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("run(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}
