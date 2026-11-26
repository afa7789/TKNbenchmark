package lru

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct{ in, want string }{
		{"2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n"},
		{"2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n"},
		{"3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n"},
		{"1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n"},
	}
	for _, tt := range tests {
		var out bytes.Buffer
		if err := Run(strings.NewReader(tt.in), &out); err != nil {
			t.Fatal(err)
		}
		if out.String() != tt.want {
			t.Errorf("Run(%q) = %q, want %q", tt.in, out.String(), tt.want)
		}
	}
}
