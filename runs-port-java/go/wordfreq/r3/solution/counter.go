package main

import (
	"cmp"
	"errors"
	"io"
	"slices"
	"strings"
)

const readBufferSize = 1 << 16

// WordCount is a word together with its number of occurrences.
type WordCount struct {
	Word  string
	Count int
}

// Counter tallies occurrences of lowercase words.
type Counter struct {
	index map[string]int // word -> position in entries
	words []WordCount
}

// NewCounter returns an empty Counter.
func NewCounter() *Counter {
	return &Counter{index: make(map[string]int)}
}

// Add records one occurrence of word. The slice is not retained.
func (c *Counter) Add(word []byte) {
	// The string(word) conversion in a map index expression does not allocate.
	if i, ok := c.index[string(word)]; ok {
		c.words[i].Count++
		return
	}
	w := string(word)
	c.index[w] = len(c.words)
	c.words = append(c.words, WordCount{Word: w, Count: 1})
}

// Top returns up to limit words ordered by count descending, then word ascending.
func (c *Counter) Top(limit int) []WordCount {
	if limit <= 0 {
		return nil
	}
	best := make([]WordCount, 0, limit+1)
	for _, wc := range c.words {
		if len(best) == limit && compareRank(wc, best[len(best)-1]) >= 0 {
			continue
		}
		pos, _ := slices.BinarySearchFunc(best, wc, compareRank)
		best = slices.Insert(best, pos, wc)
		if len(best) > limit {
			best = best[:limit]
		}
	}
	return best
}

// compareRank orders by count descending, then by word in ascending byte order.
func compareRank(a, b WordCount) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return strings.Compare(a.Word, b.Word)
}

// Count tokenizes r into maximal runs of ASCII letters, folds them to
// lowercase, and tallies them. Every other byte is a separator.
func Count(r io.Reader) (*Counter, error) {
	c := NewCounter()
	buf := make([]byte, readBufferSize)
	word := make([]byte, 0, 64)

	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			if lower := b | 0x20; lower >= 'a' && lower <= 'z' {
				word = append(word, lower)
			} else if len(word) > 0 {
				c.Add(word)
				word = word[:0]
			}
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	if len(word) > 0 {
		c.Add(word)
	}
	return c, nil
}
