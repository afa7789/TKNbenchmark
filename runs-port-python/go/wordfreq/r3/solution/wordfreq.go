package main

import (
	"bufio"
	"cmp"
	"errors"
	"fmt"
	"io"
	"slices"
)

const chunkSize = 1 << 20

// Entry is a word together with the number of times it occurred.
type Entry struct {
	Word  string
	Count int
}

// Counter tallies case-folded ASCII words.
type Counter struct {
	counts map[string]*int
}

// NewCounter returns an empty Counter.
func NewCounter() *Counter {
	return &Counter{counts: make(map[string]*int)}
}

// add records one occurrence of word. The word bytes are copied only the
// first time a distinct word is seen.
func (c *Counter) add(word []byte) {
	if n, ok := c.counts[string(word)]; ok {
		*n++
		return
	}
	n := 1
	c.counts[string(word)] = &n
}

// ReadFrom counts every word in r. A word is a maximal run of ASCII letters;
// every other byte is a separator. Words are folded to lowercase.
func (c *Counter) ReadFrom(r io.Reader) (int64, error) {
	buf := make([]byte, chunkSize)
	var word []byte
	var total int64
	for {
		n, err := r.Read(buf)
		total += int64(n)
		for _, b := range buf[:n] {
			switch {
			case 'a' <= b && b <= 'z':
				word = append(word, b)
			case 'A' <= b && b <= 'Z':
				word = append(word, b+('a'-'A'))
			case len(word) > 0:
				c.add(word)
				word = word[:0]
			}
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return total, err
		}
	}
	if len(word) > 0 {
		c.add(word)
	}
	return total, nil
}

// Top returns at most n entries ordered by count descending, then by word
// ascending in byte order.
func (c *Counter) Top(n int) []Entry {
	entries := make([]Entry, 0, len(c.counts))
	for w, cnt := range c.counts {
		entries = append(entries, Entry{Word: w, Count: *cnt})
	}
	slices.SortFunc(entries, func(a, b Entry) int {
		if a.Count != b.Count {
			return cmp.Compare(b.Count, a.Count)
		}
		return cmp.Compare(a.Word, b.Word)
	})
	if len(entries) > n {
		entries = entries[:n]
	}
	return entries
}

// WriteEntries prints entries as "<count> <word>" lines.
func WriteEntries(w io.Writer, entries []Entry) error {
	bw := bufio.NewWriter(w)
	for _, e := range entries {
		if _, err := fmt.Fprintf(bw, "%d %s\n", e.Count, e.Word); err != nil {
			return err
		}
	}
	return bw.Flush()
}
