package main

import (
	"bufio"
	"io"
	"strings"
	"testing"
)

func runTool(t *testing.T, tool func(io.Reader, *bufio.Writer) error, in string) string {
	t.Helper()
	var sb strings.Builder
	w := bufio.NewWriter(&sb)
	if err := tool(strings.NewReader(in), w); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := w.Flush(); err != nil {
		t.Fatal(err)
	}
	return sb.String()
}

func TestWordFreq(t *testing.T) {
	tests := []struct{ in, want string }{
		{"The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n"},
		{"don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n"},
		{"", ""},
		{"123 \xff\xc3(", ""},
		{"k j i h g f e d c b a a", "2 a\n1 b\n1 c\n1 d\n1 e\n1 f\n1 g\n1 h\n1 i\n1 j\n"},
	}
	for _, tt := range tests {
		if got := runTool(t, wordFreq, tt.in); got != tt.want {
			t.Errorf("wordFreq(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestLRU(t *testing.T) {
	tests := []struct{ in, want string }{
		{"2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n"},
		{"2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n"},
		{"3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n"},
		{"2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\nNULL\n3\n4\n2\n"},
	}
	for _, tt := range tests {
		if got := runTool(t, lruSim, tt.in); got != tt.want {
			t.Errorf("lruSim(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestCalc(t *testing.T) {
	tests := []struct{ expr, want string }{
		{"1 + 2 * 3", "7"},
		{"-7 / 2", "-3"},
		{"-7 % 3", "-1"},
		{"7 % -3", "1"},
		{"10 - 4 - 3", "3"},
		{"--5", "5"},
		{"-2 * 3", "-6"},
		{"\t(1 + 2) * 3 ", "9"},
		{"(-9223372036854775807 - 1) % -1", "0"},
		{"-9223372036854775807 - 1", "-9223372036854775808"},
		{"(-9223372036854775807 - 1) / -1", "error"},
		{"-(-9223372036854775807 - 1)", "error"},
		{"9223372036854775807 + 1", "error"},
		{"9223372036854775808", "error"},
		{"3037000500 * 3037000500", "error"},
		{"1 / 0", "error"},
		{"1 % 0", "error"},
		{"(1 + 2", "error"},
		{"1 + 2)", "error"},
		{"()", "error"},
		{"1 2", "error"},
		{"+1", "error"},
		{"1 +", "error"},
		{"abc", "error"},
	}
	for _, tt := range tests {
		if got := runTool(t, calc, tt.expr+"\n"); got != tt.want+"\n" {
			t.Errorf("calc(%q) = %q, want %q", tt.expr, got, tt.want)
		}
	}
	if got := runTool(t, calc, "\n  \t\n"); got != "" {
		t.Errorf("blank lines produced %q", got)
	}
}
