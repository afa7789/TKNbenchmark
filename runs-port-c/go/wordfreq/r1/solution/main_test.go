package main

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
		{"simple", "The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"empty", "", ""},
		{"no words", "123 _-' \xff\xc3(", ""},
		{"separators", "don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"top ten", "k j i h g f e d c b a a", "2 a\n1 b\n1 c\n1 d\n1 e\n1 f\n1 g\n1 h\n1 i\n1 j\n"},
		{"prefix order", "ab a abc", "1 a\n1 ab\n1 abc\n"},
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

func TestWordsSpanningReads(t *testing.T) {
	in := strings.Repeat("Hello wORld ", 1000) + "tail"
	var out bytes.Buffer
	if err := run(iotest.OneByteReader(strings.NewReader(in)), &out); err != nil {
		t.Fatal(err)
	}
	want := "1000 hello\n1000 world\n1 tail\n"
	if got := out.String(); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
