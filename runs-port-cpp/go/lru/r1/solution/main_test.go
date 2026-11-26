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
		{"spec example", "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n"},
		{"overwrite refreshes", "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c\n", "9\nNULL\n3\n"},
		{"del and size", "3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n"},
		{"capacity one", "1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE", "NULL\n2\n1\n"},
		{"crlf and blank lines", "2\r\nSET a 1\r\n\r\nGET a\r\n", "1\n"},
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
