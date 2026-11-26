package main

import (
	"cmp"
	"slices"
)

// WordCount is a word together with its number of occurrences.
type WordCount struct {
	Word  string
	Count int
}

// lower maps ASCII letters to their lower-case form and every other byte to 0.
var lower = func() (t [256]byte) {
	for c := 'A'; c <= 'Z'; c++ {
		t[c] = byte(c) | 0x20
	}
	for c := 'a'; c <= 'z'; c++ {
		t[c] = byte(c)
	}
	return t
}()

// countWords returns the occurrences of every word in buf. A word is a
// maximal run of ASCII letters, folded to lower case. buf is lower-cased in
// place while scanning.
func countWords(buf []byte) []WordCount {
	index := make(map[string]int, 1<<12) // word -> position in counts
	var counts []WordCount
	n := len(buf)
	for i := 0; i < n; {
		if lower[buf[i]] == 0 {
			i++
			continue
		}
		start := i
		for ; i < n; i++ {
			c := lower[buf[i]]
			if c == 0 {
				break
			}
			buf[i] = c
		}
		word := buf[start:i]
		// Lookups keyed by string(word) do not allocate; only new words do.
		if k, ok := index[string(word)]; ok {
			counts[k].Count++
			continue
		}
		s := string(word)
		index[s] = len(counts)
		counts = append(counts, WordCount{Word: s, Count: 1})
	}
	return counts
}

// byCountThenWord orders by count descending, then by word ascending.
func byCountThenWord(a, b WordCount) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return cmp.Compare(a.Word, b.Word)
}

// topWords returns at most limit entries of counts in byCountThenWord order.
func topWords(counts []WordCount, limit int) []WordCount {
	top := make([]WordCount, 0, limit+1)
	for _, wc := range counts {
		if len(top) == limit && byCountThenWord(wc, top[limit-1]) >= 0 {
			continue
		}
		pos, _ := slices.BinarySearchFunc(top, wc, byCountThenWord)
		top = slices.Insert(top, pos, wc)
		if len(top) > limit {
			top = top[:limit]
		}
	}
	return top
}
