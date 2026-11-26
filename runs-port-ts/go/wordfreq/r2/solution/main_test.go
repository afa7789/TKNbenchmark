package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"simple", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"case folding", "Hello, hello! HELLO? world.\n", "3 hello\n1 world\n"},
		{"top ten and ties",
			"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
			"2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n"},
		{"empty", "", ""},
		{"no words", "123 _' \xff\xc3(", ""},
		{"separators", "don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"high bytes", "caf\xc3\xa9 CAF\xffe", "2 caf\n1 e\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var out bytes.Buffer
			if err := run(strings.NewReader(tt.in), &out); err != nil {
				t.Fatal(err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}
