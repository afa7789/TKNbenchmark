package main

import (
	"reflect"
	"strings"
	"testing"
)

func TestCountAndTop(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []Entry
	}{
		{"empty", "", nil},
		{"no words", "123 _ ' \xff\xc3(", nil},
		{"simple", "The cat and the hat.", []Entry{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"separators", "don't stop_me 4now, now-NOW", []Entry{{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}}},
		{"non-letters near letters", "a@b[c`d{e\x80f\xc1g", []Entry{{"a", 1}, {"b", 1}, {"c", 1}, {"d", 1}, {"e", 1}, {"f", 1}, {"g", 1}}},
		{"top ten", "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha", []Entry{
			{"alpha", 2}, {"beta", 1}, {"eta", 1}, {"iota", 1}, {"kappa", 1},
			{"lambda", 1}, {"mu", 1}, {"nu", 1}, {"omicron", 1}, {"pi", 1},
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			counts, err := Count(strings.NewReader(tt.input))
			if err != nil {
				t.Fatal(err)
			}
			got := Top(counts, 10)
			if len(got) == 0 && len(tt.want) == 0 {
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCountAcrossReadBoundary(t *testing.T) {
	input := strings.Repeat(" ", readBufferSize-2) + "Word word"
	counts, err := Count(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if got := counts["word"]; got != 2 || len(counts) != 1 {
		t.Errorf("counts = %v, want map[word:2]", counts)
	}
}
