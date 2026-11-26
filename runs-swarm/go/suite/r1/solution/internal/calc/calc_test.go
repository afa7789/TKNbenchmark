package calc

import (
	"bytes"
	"strings"
	"testing"
)

func TestEval(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		err  bool
	}{
		{in: "1 + 2 * 3", want: 7},
		{in: "-7 / 2", want: -3},
		{in: "-7 % 3", want: -1},
		{in: "7 % -3", want: 1},
		{in: "10 - 4 - 3", want: 3},
		{in: "100 / 10 / 5", want: 2},
		{in: "--5", want: 5},
		{in: "2 * -3", want: -6},
		{in: "-(2 + 3)", want: -5},
		{in: "-2 * 3", want: -6},
		{in: "((((7))))", want: 7},
		{in: "007", want: 7},
		{in: "9223372036854775807", want: 9223372036854775807},
		{in: "-9223372036854775807 - 1", want: -9223372036854775808},
		{in: "(-9223372036854775807 - 1) % -1", want: 0},
		{in: "-9223372036854775807-1+9223372036854775807", want: -1},
		{in: "\t1\t+ 1 ", want: 2},
		{in: "9223372036854775808", err: true},
		{in: "-9223372036854775808", err: true},
		{in: "9223372036854775807 + 1", err: true},
		{in: "(-9223372036854775807 - 1) - 1", err: true},
		{in: "(-9223372036854775807 - 1) / -1", err: true},
		{in: "(-9223372036854775807 - 1) * -1", err: true},
		{in: "-(-9223372036854775807 - 1)", err: true},
		{in: "4294967296 * 4294967296", err: true},
		{in: "3037000500 * 3037000500", err: true},
		{in: "1 / 0", err: true},
		{in: "1 % 0", err: true},
		{in: "(1 + 2", err: true},
		{in: "1 + 2)", err: true},
		{in: "()", err: true},
		{in: "1 +", err: true},
		{in: "1 2", err: true},
		{in: "+1", err: true},
		{in: "abc", err: true},
		{in: "1 + 2\r", err: true},
		{in: "(1)(2)", err: true},
		{in: "1 * / 2", err: true},
		{in: "-", err: true},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if tt.err {
			if err == nil {
				t.Errorf("Eval(%q) = %d, want error", tt.in, got)
			}
			continue
		}
		if err != nil || got != tt.want {
			t.Errorf("Eval(%q) = %d, %v; want %d", tt.in, got, err, tt.want)
		}
	}
}

func TestEvalDeepNesting(t *testing.T) {
	const depth = 1_000_000
	expr := strings.Repeat("(", depth) + "1" + strings.Repeat(")", depth)
	if got, err := Eval([]byte(expr)); err != nil || got != 1 {
		t.Fatalf("deep parens = %d, %v; want 1", got, err)
	}
	expr = strings.Repeat("-", depth) + "1"
	if got, err := Eval([]byte(expr)); err != nil || got != 1 {
		t.Fatalf("deep negation = %d, %v; want 1", got, err)
	}
}

func TestRun(t *testing.T) {
	in := "1 + 2 * 3\n-7 / 2\n\n  \t\n(1 + 2\n9223372036854775807 + 1\n" +
		strings.Repeat("1+", 100_000) + "1"
	want := "7\n-3\nerror\nerror\n100001\n"
	var out bytes.Buffer
	if err := Run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if out.String() != want {
		t.Errorf("Run output = %q, want %q", out.String(), want)
	}
}
