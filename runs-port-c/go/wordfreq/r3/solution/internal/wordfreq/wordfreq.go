// Package wordfreq counts ASCII-letter words and ranks them by frequency.
//
// A word is a maximal run of [A-Za-z], folded to lowercase. Every other byte
// is a separator.
package wordfreq

import (
	"cmp"
	"errors"
	"io"
	"slices"
)

const readChunk = 64 << 10

// WordCount is a distinct word and the number of times it occurred.
type WordCount struct {
	Word  string
	Count int
}

// Counter accumulates word frequencies.
type Counter struct {
	counts map[string]int
}

// NewCounter returns an empty Counter.
func NewCounter() *Counter {
	return &Counter{counts: make(map[string]int, 4096)}
}

func isLetter(c byte) bool {
	return (c|0x20)-'a' < 26
}

// ReadFrom counts every word in r. Words spanning read boundaries are
// handled correctly. It implements io.ReaderFrom.
func (c *Counter) ReadFrom(r io.Reader) (int64, error) {
	buf := make([]byte, readChunk)
	var pending []byte // word prefix carried over from the previous chunk
	var total int64
	for {
		n, err := r.Read(buf)
		total += int64(n)
		pending = c.scan(buf[:n], pending)
		if err != nil {
			if len(pending) > 0 {
				c.add(pending)
			}
			if errors.Is(err, io.EOF) {
				return total, nil
			}
			return total, err
		}
	}
}

// scan counts the complete words in chunk, which follows the partial word
// pending. It lowercases chunk in place and returns the new partial word.
func (c *Counter) scan(chunk, pending []byte) []byte {
	i := 0
	for i < len(chunk) {
		if !isLetter(chunk[i]) {
			if len(pending) > 0 {
				c.add(pending)
				pending = pending[:0]
			}
			i++
			continue
		}
		start := i
		for i < len(chunk) && isLetter(chunk[i]) {
			chunk[i] |= 0x20
			i++
		}
		word := chunk[start:i]
		if i < len(chunk) && len(pending) == 0 {
			c.add(word) // entirely inside this chunk: no copy needed
		} else {
			pending = append(pending, word...)
		}
	}
	return pending
}

// add records one occurrence of the lowercase word w.
func (c *Counter) add(w []byte) {
	c.counts[string(w)]++
}

// Top returns up to n words ordered by count descending, then by word in
// ascending byte order.
func (c *Counter) Top(n int) []WordCount {
	if n <= 0 {
		return nil
	}
	top := make([]WordCount, 0, n+1)
	for w, cnt := range c.counts {
		wc := WordCount{Word: w, Count: cnt}
		if len(top) == n && !ranksBefore(wc, top[n-1]) {
			continue
		}
		i, _ := slices.BinarySearchFunc(top, wc, compare)
		top = slices.Insert(top, i, wc)
		if len(top) > n {
			top = top[:n]
		}
	}
	return top
}

func compare(a, b WordCount) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return cmp.Compare(a.Word, b.Word) // string order is byte order
}

func ranksBefore(a, b WordCount) bool {
	return compare(a, b) < 0
}
