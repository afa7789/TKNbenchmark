package wordfreq

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct{ in, want string }{
		{"The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"", ""},
		{"caf\xc3\xa9 CAF\xffe", "2 caf\n1 e\n"},
	}
	for _, tt := range tests {
		var out bytes.Buffer
		if err := Run(strings.NewReader(tt.in), &out, 10); err != nil {
			t.Fatal(err)
		}
		if out.String() != tt.want {
			t.Errorf("Run(%q) = %q, want %q", tt.in, out.String(), tt.want)
		}
	}
}
