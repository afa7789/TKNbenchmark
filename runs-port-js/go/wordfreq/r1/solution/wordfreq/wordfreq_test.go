package wordfreq

import (
	"slices"
	"strings"
	"testing"
)

func TestTop(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []Entry
	}{
		{"empty", "", []Entry{}},
		{"simple", "The cat and the hat.", []Entry{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"separators", "don't stop_me 4now, now-NOW", []Entry{{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}}},
		{"high bytes", "caf\xe9 CAF\xc3\xa9", []Entry{{"caf", 2}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := NewCounter()
			if _, err := c.ReadFrom(strings.NewReader(tt.input)); err != nil {
				t.Fatal(err)
			}
			if got := c.Top(10); !slices.Equal(got, tt.want) {
				t.Errorf("Top(10) = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestTopLimit(t *testing.T) {
	c := NewCounter()
	c.Write([]byte("k j i h g f e d c b a a"))
	c.Flush()
	got := c.Top(3)
	want := []Entry{{"a", 2}, {"b", 1}, {"c", 1}}
	if !slices.Equal(got, want) {
		t.Errorf("Top(3) = %v, want %v", got, want)
	}
}

// Words split across Write calls must be joined, at any split point.
func TestChunkBoundaries(t *testing.T) {
	const input = "Hello wORld, hello  world!xyz"
	want := []Entry{{"hello", 2}, {"world", 2}, {"xyz", 1}}
	for size := 1; size <= len(input); size++ {
		c := NewCounter()
		for i := 0; i < len(input); i += size {
			c.Write([]byte(input[i:min(i+size, len(input))]))
		}
		c.Flush()
		if got := c.Top(10); !slices.Equal(got, want) {
			t.Errorf("chunk size %d: Top(10) = %v, want %v", size, got, want)
		}
	}
}
