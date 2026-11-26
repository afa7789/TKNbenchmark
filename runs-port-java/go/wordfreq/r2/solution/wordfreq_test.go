package main

import (
	"slices"
	"strings"
	"testing"
)

func TestCountWords(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  map[string]int
	}{
		{"empty", "", map[string]int{}},
		{"case folding", "Hello, hello! HELLO? world.\n", map[string]int{"hello": 3, "world": 1}},
		{"separators", "don't stop_me 4now, now-NOW", map[string]int{"don": 1, "t": 1, "stop": 1, "me": 1, "now": 3}},
		{"non-ascii bytes", "caf\xc3\xa9\xff@[`{Z", map[string]int{"caf": 1, "z": 1}},
		{"trailing word", "abc", map[string]int{"abc": 1}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := CountWords(strings.NewReader(tt.input))
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != len(tt.want) {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
			for w, c := range tt.want {
				if got[w] != c {
					t.Errorf("count[%q] = %d, want %d", w, got[w], c)
				}
			}
		})
	}
}

func TestTop(t *testing.T) {
	counts := map[string]int{"the": 2, "cat": 1, "and": 1, "hat": 1}
	got := Top(counts, 10)
	want := []Entry{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}
	if !slices.Equal(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
	if got := Top(counts, 2); len(got) != 2 {
		t.Errorf("limit not applied: %v", got)
	}
}
