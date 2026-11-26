package wordfreq

import (
	"io"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{"empty", "", ""},
		{"no words", "123 _ ' !?\n", ""},
		{"example", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"separators", "don't x_y a1b caf\xc3\xa9 \xff\xfeab", "1 a\n1 ab\n1 b\n1 caf\n1 don\n1 t\n1 x\n1 y\n"},
		{"top ten", "k j i h g f e d c b a a", "2 a\n1 b\n1 c\n1 d\n1 e\n1 f\n1 g\n1 h\n1 i\n1 j\n"},
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

// oneByteReader returns at most one byte per Read, exercising words that
// span read boundaries.
type oneByteReader struct{ s string }

func (r *oneByteReader) Read(p []byte) (int, error) {
	if len(r.s) == 0 {
		return 0, io.EOF
	}
	n := copy(p[:1], r.s)
	r.s = r.s[n:]
	return n, nil
}

func TestRunSplitReads(t *testing.T) {
	var out strings.Builder
	if err := Run(&oneByteReader{"Hello hELLO world"}, &out); err != nil {
		t.Fatal(err)
	}
	if got, want := out.String(), "2 hello\n1 world\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
