package main

import (
	"slices"
	"strings"
	"testing"
	"testing/iotest"
)

func TestTopWords(t *testing.T) {
	tests := []struct {
		name, in string
		want     []entry
	}{
		{"empty", "", nil},
		{"simple", "The cat and the hat.", []entry{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"separators", "don't stop_me 4now, now-NOW\xff\xc3(", []entry{{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}}},
		{"limit", "k j i h g f e d c b a a", []entry{{"a", 2}, {"b", 1}, {"c", 1}, {"d", 1}, {"e", 1}, {"f", 1}, {"g", 1}, {"h", 1}, {"i", 1}, {"j", 1}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// OneByteReader forces words to span read boundaries.
			counts, err := countWords(iotest.OneByteReader(strings.NewReader(tt.in)))
			if err != nil {
				t.Fatal(err)
			}
			if got := topWords(counts, topN); !slices.Equal(got, tt.want) {
				t.Errorf("got %v, want %v", got, tt.want)
			}
		})
	}
}
