package main

import (
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
		{in: "--5", want: 5},
		{in: "10 - 4 - 3", want: 3},
		{in: "(-9223372036854775807 - 1) % -1", want: 0},
		{in: "-9223372036854775807 - 1", want: -9223372036854775808},
		{in: "9223372036854775807", want: 9223372036854775807},
		{in: "007", want: 7},
		{in: "\t( 1 )\t", want: 1},
		{in: "-9223372036854775808", err: true},
		{in: "9223372036854775807 + 1", err: true},
		{in: "(-9223372036854775807 - 1) / -1", err: true},
		{in: "(-9223372036854775807 - 1) * -1", err: true},
		{in: "-(-9223372036854775807 - 1)", err: true},
		{in: "3037000500 * 3037000500", err: true},
		{in: "1 / 0", err: true},
		{in: "1 % 0", err: true},
		{in: "(1 + 2", err: true},
		{in: "1 + 2)", err: true},
		{in: "()", err: true},
		{in: "1 2", err: true},
		{in: "+1", err: true},
		{in: "1 +", err: true},
		{in: "1\r", err: true},
	}
	for _, tt := range tests {
		got, err := Eval([]byte(tt.in))
		if (err != nil) != tt.err || (!tt.err && got != tt.want) {
			t.Errorf("Eval(%q) = %d, %v; want %d, err=%v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestRun(t *testing.T) {
	var out strings.Builder
	if err := run(strings.NewReader("\n  42  \n\t\n1+1\n1/0"), &out); err != nil {
		t.Fatal(err)
	}
	if got, want := out.String(), "42\n2\nerror\n"; got != want {
		t.Errorf("run output = %q, want %q", got, want)
	}
}

func TestDeepNesting(t *testing.T) {
	const n = 100000
	src := strings.Repeat("(", n) + "1" + strings.Repeat(")", n)
	if v, err := Eval([]byte(src)); err != nil || v != 1 {
		t.Errorf("deep nesting: got %d, %v", v, err)
	}
}
