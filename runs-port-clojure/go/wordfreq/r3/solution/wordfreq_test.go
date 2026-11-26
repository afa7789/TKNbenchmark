package main

import (
	"slices"
	"strings"
	"testing"
)

func TestCountWordsAndTop(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want []WordCount
	}{
		{"simple", "The cat and the hat.", []WordCount{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"empty", "", nil},
		{"separators", "don't stop_me 4now, now-NOW\xff\xc3(x", []WordCount{
			{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}, {"x", 1},
		}},
		{"limit", "k j i h g f e d c b a a", []WordCount{
			{"a", 2}, {"b", 1}, {"c", 1}, {"d", 1}, {"e", 1}, {"f", 1}, {"g", 1}, {"h", 1}, {"i", 1}, {"j", 1},
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			counts, err := CountWords(strings.NewReader(tt.in))
			if err != nil {
				t.Fatal(err)
			}
			got := TopWords(counts, topN)
			if !slices.Equal(got, tt.want) && !(len(got) == 0 && len(tt.want) == 0) {
				t.Errorf("got %v, want %v", got, tt.want)
			}
		})
	}
}
