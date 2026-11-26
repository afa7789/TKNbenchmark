package wordfreq

import (
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
		{"no words", "123 _' \xff\x80 !?", ""},
		{"separators", "a1b_c'd\xc3\xa9e", "1 a\n1 b\n1 c\n1 d\n1 e\n"},
		{"case folding", "Hello hELLO HELLO", "3 hello\n"},
		{"top ten ties", "k j i h g f e d c b a a",
			"2 a\n1 b\n1 c\n1 d\n1 e\n1 f\n1 g\n1 h\n1 i\n1 j\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var out strings.Builder
			if err := Run(strings.NewReader(tt.in), &out); err != nil {
				t.Fatal(err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}

// TestRunSplitReads checks that words spanning read boundaries are kept whole.
func TestRunSplitReads(t *testing.T) {
	var out strings.Builder
	r := iotest.OneByteReader(strings.NewReader("Alpha beta ALPHA"))
	if err := Run(r, &out); err != nil {
		t.Fatal(err)
	}
	if got, want := out.String(), "2 alpha\n1 beta\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
