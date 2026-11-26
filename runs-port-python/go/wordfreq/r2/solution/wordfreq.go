package main

import (
	"cmp"
	"errors"
	"io"
	"slices"
)

// entry is a word together with its number of occurrences.
type entry struct {
	word  string
	count int
}

// lowerTable maps ASCII letters to their lowercase form and every other byte
// to 0, which marks a separator.
var lowerTable = func() (t [256]byte) {
	for c := 'a'; c <= 'z'; c++ {
		t[c] = byte(c)
		t[c-'a'+'A'] = byte(c)
	}
	return t
}()

// countWords reads r to EOF and returns how often each lowercased word
// (maximal run of ASCII letters) occurs.
func countWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, 64*1024)
	word := make([]byte, 0, 64) // current word; may span reads

	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			if c := lowerTable[b]; c != 0 {
				word = append(word, c)
			} else if len(word) > 0 {
				counts[string(word)]++ // no allocation when the key exists
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

// compareEntries orders entries by count descending, then by word ascending.
func compareEntries(a, b entry) int {
	if c := cmp.Compare(b.count, a.count); c != 0 {
		return c
	}
	return cmp.Compare(a.word, b.word)
}

// topWords returns up to n entries from counts, ordered by count descending
// and then by word ascending.
func topWords(counts map[string]int, n int) []entry {
	if n <= 0 {
		return nil
	}
	top := make([]entry, 0, n+1)
	for word, count := range counts {
		e := entry{word, count}
		if len(top) == n && compareEntries(e, top[n-1]) >= 0 {
			continue
		}
		i, _ := slices.BinarySearchFunc(top, e, compareEntries)
		top = slices.Insert(top, i, e)
		if len(top) > n {
			top = top[:n]
		}
	}
	return top
}
