package main

import (
	"cmp"
	"errors"
	"io"
	"slices"
	"strings"
)

const readBufferSize = 1 << 16

// Entry is a word together with its number of occurrences.
type Entry struct {
	Word  string
	Count int
}

// Count reads r to EOF and returns the number of occurrences of each word.
// A word is a maximal run of ASCII letters, folded to lowercase; every other
// byte is a separator.
func Count(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, readBufferSize)
	word := make([]byte, 0, 64)
	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			// Setting bit 0x20 maps 'A'..'Z' onto 'a'..'z' and leaves
			// lowercase letters unchanged; no other byte lands in 'a'..'z'.
			if lower := b | 0x20; lower >= 'a' && lower <= 'z' {
				word = append(word, lower)
			} else if len(word) > 0 {
				counts[string(word)]++
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
		counts[string(word)]++
	}
	return counts, nil
}

// compareEntries orders entries by count descending, then word ascending.
func compareEntries(a, b Entry) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return strings.Compare(a.Word, b.Word)
}

// Top returns at most limit entries from counts, ordered by count descending
// and then by word ascending (byte order).
func Top(counts map[string]int, limit int) []Entry {
	if limit <= 0 {
		return nil
	}
	// Keep a small sorted slice of the best entries seen so far; limit is
	// tiny compared to the number of distinct words.
	top := make([]Entry, 0, limit+1)
	for w, c := range counts {
		e := Entry{Word: w, Count: c}
		if len(top) == limit && compareEntries(e, top[limit-1]) >= 0 {
			continue
		}
		i, _ := slices.BinarySearchFunc(top, e, compareEntries)
		top = slices.Insert(top, i, e)
		if len(top) > limit {
			top = top[:limit]
		}
	}
	return top
}
