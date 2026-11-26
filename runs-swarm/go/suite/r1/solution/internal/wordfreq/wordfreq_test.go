package wordfreq

import (
	"bytes"
	"strings"
	"testing"
	"testing/iotest"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"example", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"empty", "", ""},
		{"no words", "123 _ ' !? \xff\xfe", ""},
		{"case folding", "Hello hELLo HELLO world", "3 hello\n1 world\n"},
		{"separators", "a1b_c'd\xc3\xa9e", "1 a\n1 b\n1 c\n1 d\n1 e\n"},
		{"trailing word", "x y x", "2 x\n1 y\n"},
		{
			"top ten with ties",
			"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
			"2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
		},
		{"byte order", "b B a A ab", "2 a\n2 b\n1 ab\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var out bytes.Buffer
			// OneByteReader forces words to span reads.
			if err := Run(iotest.OneByteReader(strings.NewReader(tt.in)), &out); err != nil {
				t.Fatal(err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func TestRunReadError(t *testing.T) {
	r := iotest.TimeoutReader(strings.NewReader("abc"))
	if err := Run(iotest.OneByteReader(r), new(bytes.Buffer)); err == nil {
		t.Fatal("expected error")
	}
}
