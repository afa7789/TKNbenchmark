package main

import (
	"cmp"
	"errors"
	"io"
	"slices"
	"strings"
)

const readBufferSize = 64 << 10

// Entry is a word together with its number of occurrences.
type Entry struct {
	Word  string
	Count int
}

// CountWords reads r to EOF and returns the occurrence count of every word.
// A word is a maximal run of ASCII letters, folded to lowercase; every other
// byte is a separator.
func CountWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, readBufferSize)
	word := make([]byte, 0, 64)

	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
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

// Top returns at most limit entries ordered by count descending, with ties
// broken by word in ascending byte order.
func Top(counts map[string]int, limit int) []Entry {
	entries := make([]Entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, Entry{Word: w, Count: c})
	}
	slices.SortFunc(entries, func(a, b Entry) int {
		if c := cmp.Compare(b.Count, a.Count); c != 0 {
			return c
		}
		return strings.Compare(a.Word, b.Word)
	})
	return entries[:min(limit, len(entries))]
}
