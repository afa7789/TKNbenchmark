// Package wordfreq counts case-insensitive ASCII-letter words and ranks them.
package wordfreq

import (
	"cmp"
	"slices"
)

// Entry is a word together with its number of occurrences.
type Entry struct {
	Word  string
	Count int
}

// Count returns the occurrences of each word in data. A word is a maximal run
// of ASCII letters; every other byte is a separator. Words are folded to
// lowercase. Count lowercases data in place.
func Count(data []byte) map[string]int {
	counts := make(map[string]int)
	start := -1
	for i, c := range data {
		switch {
		case 'a' <= c && c <= 'z':
		case 'A' <= c && c <= 'Z':
			data[i] = c | 0x20
		default:
			if start >= 0 {
				counts[string(data[start:i])]++
				start = -1
			}
			continue
		}
		if start < 0 {
			start = i
		}
	}
	if start >= 0 {
		counts[string(data[start:])]++
	}
	return counts
}

// compare orders entries by count descending, then word ascending.
func compare(a, b Entry) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return cmp.Compare(a.Word, b.Word)
}

// Top returns up to n entries of counts, ranked by count descending with
// ties broken by word in ascending byte order.
func Top(counts map[string]int, n int) []Entry {
	if n <= 0 {
		return nil
	}
	top := make([]Entry, 0, min(n, len(counts))+1)
	for word, count := range counts {
		e := Entry{Word: word, Count: count}
		if len(top) == n && compare(e, top[n-1]) >= 0 {
			continue
		}
		i, _ := slices.BinarySearchFunc(top, e, compare)
		top = slices.Insert(top, i, e)
		if len(top) > n {
			top = top[:n]
		}
	}
	return top
}
