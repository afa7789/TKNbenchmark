package main

import (
	"bufio"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct{ name, in, want string }{
		{"spec example", "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n"},
		{"overwrite refreshes", "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n"},
		{"del and size", "3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n"},
		{"capacity one", "1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n"},
		{"crlf", "2\r\nSET a 1\r\nGET a\r\n", "1\n"},
		{"get refreshes", "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\n", "1\n1\nNULL\n"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var sb strings.Builder
			w := bufio.NewWriter(&sb)
			if err := run(strings.NewReader(tt.in), w); err != nil {
				t.Fatal(err)
			}
			w.Flush()
			if got := sb.String(); got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func TestEvictionReusesEntries(t *testing.T) {
	c := NewCache(3)
	for i := range 1000 {
		c.Set(string(rune('a'+i%26))+string(rune('a'+i/26)), "v")
	}
	if c.Len() != 3 || len(c.entries) != 3 {
		t.Fatalf("len=%d pool=%d, want 3 and 3", c.Len(), len(c.entries))
	}
}
