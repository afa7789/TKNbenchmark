package main

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"simple", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"case folding", "Hello, hello! HELLO? world.\n", "3 hello\n1 world\n"},
		{"empty", "", ""},
		{"separators", "don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"high bytes", "caf\xc3\xa9\xffcaf", "2 caf\n"},
		{
			"top ten and ties",
			"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
			"2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var out strings.Builder
			if err := run(strings.NewReader(tc.in), &out); err != nil {
				t.Fatal(err)
			}
			if got := out.String(); got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}
