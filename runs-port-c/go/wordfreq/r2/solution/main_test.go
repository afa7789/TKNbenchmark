package main

import (
	"reflect"
	"strings"
	"testing"
	"testing/iotest"
)

func run(t *testing.T, input string) []entry {
	t.Helper()
	counts, err := countWords(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	return top(counts, topN)
}

func TestExamples(t *testing.T) {
	tests := []struct {
		in   string
		want []entry
	}{
		{"The cat and the hat.", []entry{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"don't stop_me 4now, now-NOW", []entry{{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}}},
		{"", []entry{}},
		{"123 \xff\xc3( ...", []entry{}},
		{"caf\xc3\xa9 CAF", []entry{{"caf", 2}}},
	}
	for _, tt := range tests {
		got := run(t, tt.in)
		if len(got) == 0 && len(tt.want) == 0 {
			continue
		}
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("%q: got %v, want %v", tt.in, got, tt.want)
		}
	}
}

func TestWordAcrossChunks(t *testing.T) {
	long := strings.Repeat("a", readChunk*3+7)
	input := strings.Repeat("x", readChunk-2) + "yz " + long + " " + long
	counts, err := countWords(iotest.OneByteReader(strings.NewReader(input)))
	if err != nil {
		t.Fatal(err)
	}
	if counts[long] != 2 || counts[strings.Repeat("x", readChunk-2)+"yz"] != 1 || len(counts) != 2 {
		t.Errorf("unexpected counts: %d words", len(counts))
	}
}

func TestTopLimit(t *testing.T) {
	got := run(t, "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha")
	want := []entry{{"alpha", 2}, {"beta", 1}, {"eta", 1}, {"iota", 1}, {"kappa", 1},
		{"lambda", 1}, {"mu", 1}, {"nu", 1}, {"omicron", 1}, {"pi", 1}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}
