package main

import (
	"cmp"
	"errors"
	"io"
	"slices"
)

const bufferSize = 64 * 1024

// WordCount pairs a lowercase word with its number of occurrences.
type WordCount struct {
	Word  string
	Count int
}

// lowerASCII reports whether b is an ASCII letter and returns its lowercase form.
func lowerASCII(b byte) (byte, bool) {
	switch {
	case 'a' <= b && b <= 'z':
		return b, true
	case 'A' <= b && b <= 'Z':
		return b + ('a' - 'A'), true
	default:
		return 0, false
	}
}

// CountWords streams r and returns the number of occurrences of each word,
// where a word is a maximal run of ASCII letters folded to lowercase.
func CountWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, bufferSize)
	word := make([]byte, 0, 64)

	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			if c, ok := lowerASCII(b); ok {
				word = append(word, c)
			} else if len(word) > 0 {
				counts[string(word)]++ // the conversion does not allocate for existing keys
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

// compareWordCounts orders by count descending, then word ascending.
func compareWordCounts(a, b WordCount) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return cmp.Compare(a.Word, b.Word)
}

// TopWords returns up to n entries of counts, most frequent first,
// with ties broken by word in ascending byte order.
func TopWords(counts map[string]int, n int) []WordCount {
	if n <= 0 {
		return nil
	}
	// Keep a small sorted slice of the best n entries seen so far.
	top := make([]WordCount, 0, n+1)
	for w, c := range counts {
		wc := WordCount{Word: w, Count: c}
		if len(top) == n && compareWordCounts(wc, top[n-1]) >= 0 {
			continue
		}
		i, _ := slices.BinarySearchFunc(top, wc, compareWordCounts)
		top = slices.Insert(top, i, wc)
		if len(top) > n {
			top = top[:n]
		}
	}
	return top
}
