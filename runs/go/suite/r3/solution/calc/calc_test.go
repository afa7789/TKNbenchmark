package calc

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	in := strings.Join([]string{
		"1 + 2 * 3", "-7 / 2", "(1 + 2", "9223372036854775807 + 1",
		"", "  \t", "-7 % 3", "7 % -3", "1 / 0",
		"(-9223372036854775807 - 1) % -1", "(-9223372036854775807 - 1) / -1",
		"-(-9223372036854775807 - 1)", "9223372036854775808", "--5", "+1", "()", "1 2",
	}, "\n")
	want := "7\n-3\nerror\nerror\n-1\n1\nerror\n0\nerror\nerror\nerror\n5\nerror\nerror\nerror\n"
	var out bytes.Buffer
	if err := Run(strings.NewReader(in), &out); err != nil {
		t.Fatal(err)
	}
	if out.String() != want {
		t.Errorf("got:\n%s\nwant:\n%s", out.String(), want)
	}
}
