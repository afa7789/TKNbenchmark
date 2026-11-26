package main

import (
	"slices"
	"strings"
	"testing"
)

func TestCountTop(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []WordCount
	}{
		{"empty", "", nil},
		{"no words", "123 _' \xff\xc3(", nil},
		{"simple", "The cat and the hat.", []WordCount{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"separators", "don't stop_me 4now, now-NOW", []WordCount{{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}}},
		{"non-letters near letters", "a@b[c`d{e\xc1f\xe1g", []WordCount{{"a", 1}, {"b", 1}, {"c", 1}, {"d", 1}, {"e", 1}, {"f", 1}, {"g", 1}}},
		{"limit", "k j i h g f e d c b a a", []WordCount{{"a", 2}, {"b", 1}, {"c", 1}, {"d", 1}, {"e", 1}, {"f", 1}, {"g", 1}, {"h", 1}, {"i", 1}, {"j", 1}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, err := Count(strings.NewReader(tt.input))
			if err != nil {
				t.Fatal(err)
			}
			if got := c.Top(topN); !slices.Equal(got, tt.want) {
				t.Errorf("Top = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestWordSpanningReads(t *testing.T) {
	long := strings.Repeat("Ab", readBufferSize)
	c, err := Count(strings.NewReader(long + " " + long))
	if err != nil {
		t.Fatal(err)
	}
	got := c.Top(topN)
	if len(got) != 1 || got[0].Count != 2 || got[0].Word != strings.ToLower(long) {
		t.Errorf("unexpected result: %d entries", len(got))
	}
}
