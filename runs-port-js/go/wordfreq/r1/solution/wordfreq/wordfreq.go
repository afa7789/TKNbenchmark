// Package wordfreq counts case-insensitive ASCII words in a byte stream.
//
// A word is a maximal run of ASCII letters; every other byte is a separator.
package wordfreq

import (
	"cmp"
	"errors"
	"io"
	"slices"
)

const readBufSize = 256 << 10

// Entry is a word together with its number of occurrences.
type Entry struct {
	Word  string
	Count int
}

// Counter accumulates word frequencies. The zero value is not usable;
// create one with NewCounter.
type Counter struct {
	index   map[string]int // word -> position in entries
	entries []Entry
	pending []byte // lowercased letters of a word that may continue in the next chunk
}

// NewCounter returns an empty Counter.
func NewCounter() *Counter {
	return &Counter{index: make(map[string]int)}
}

// Write feeds p to the counter. A word at the end of p is held back until a
// separator arrives or Flush is called. Write never returns an error.
func (c *Counter) Write(p []byte) (int, error) {
	start := -1
	for i, b := range p {
		if isLetter(b) {
			if start < 0 {
				start = i
			}
			continue
		}
		if start >= 0 {
			c.addWord(p[start:i])
			start = -1
		} else if len(c.pending) > 0 {
			c.addWord(nil)
		}
	}
	if start >= 0 {
		c.pending = appendLower(c.pending, p[start:])
	}
	return len(p), nil
}

// ReadFrom consumes r until EOF and then flushes any trailing word.
func (c *Counter) ReadFrom(r io.Reader) (int64, error) {
	buf := make([]byte, readBufSize)
	var total int64
	for {
		n, err := r.Read(buf)
		if n > 0 {
			total += int64(n)
			c.Write(buf[:n])
		}
		if errors.Is(err, io.EOF) {
			c.Flush()
			return total, nil
		}
		if err != nil {
			return total, err
		}
	}
}

// Flush counts any word held back at the end of the input.
func (c *Counter) Flush() {
	if len(c.pending) > 0 {
		c.addWord(nil)
	}
}

// Top returns up to n entries ordered by count descending, then by word
// ascending in byte order.
func (c *Counter) Top(n int) []Entry {
	entries := slices.Clone(c.entries)
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

// addWord counts the pending prefix followed by the letters in tail.
func (c *Counter) addWord(tail []byte) {
	c.pending = appendLower(c.pending, tail)
	// The string conversion in a map lookup does not allocate, so only the
	// first occurrence of each word copies it into a new string.
	if i, ok := c.index[string(c.pending)]; ok {
		c.entries[i].Count++
	} else {
		w := string(c.pending)
		c.index[w] = len(c.entries)
		c.entries = append(c.entries, Entry{Word: w, Count: 1})
	}
	c.pending = c.pending[:0]
}

func appendLower(dst, src []byte) []byte {
	for _, b := range src {
		dst = append(dst, b|0x20)
	}
	return dst
}

func isLetter(b byte) bool {
	b |= 0x20
	return b >= 'a' && b <= 'z'
}
