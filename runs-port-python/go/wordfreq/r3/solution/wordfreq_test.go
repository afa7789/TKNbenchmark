package main

import (
	"bytes"
	"strings"
	"testing"
	"testing/iotest"
)

func TestCounter(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"simple", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"folding", "Hello, hello! HELLO? world.\n", "3 hello\n1 world\n"},
		{"separators", "don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"high bytes", "ab\xffcd\xc3(ab", "2 ab\n1 cd\n"},
		{"empty", "", ""},
		{"no words", "123 _-'\x80", ""},
		{"top10", "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
			"2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := NewCounter()
			// OneByteReader exercises words spanning read boundaries.
			if _, err := c.ReadFrom(iotest.OneByteReader(strings.NewReader(tt.in))); err != nil {
				t.Fatal(err)
			}
			var out bytes.Buffer
			if err := WriteEntries(&out, c.Top(topN)); err != nil {
				t.Fatal(err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}
