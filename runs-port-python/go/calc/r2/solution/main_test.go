package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	in := "1 + 2 * 3\n\n  \t\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n" + strings.Repeat(" ", 200_000) + "5"
	var out bytes.Buffer
	if err := run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if want := "7\n-3\nerror\nerror\n5\n"; out.String() != want {
		t.Errorf("output = %q, want %q", out.String(), want)
	}
}
