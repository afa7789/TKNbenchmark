// Package wordfreq implements the wordfreq subcommand: it prints the ten
// most frequent words of its input.
package wordfreq

import (
	"errors"
	"fmt"
	"io"
)

// topN is the maximum number of words reported.
const topN = 10

// entry is a distinct word and the number of times it occurred.
type entry struct {
	word  string
	count int
}

// less reports whether a ranks before b: higher count first, then
// ascending byte order of the word.
func (a entry) less(b entry) bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// counter accumulates word frequencies.
type counter struct {
	index   map[string]int // word -> position in entries
	entries []entry
}

func newCounter() *counter {
	return &counter{index: make(map[string]int)}
}

// add records one occurrence of word. word is not retained.
func (c *counter) add(word []byte) {
	// The map lookup with a string(word) conversion does not allocate;
	// a copy is made only when a new word is first seen.
	if i, ok := c.index[string(word)]; ok {
		c.entries[i].count++
		return
	}
	s := string(word)
	c.index[s] = len(c.entries)
	c.entries = append(c.entries, entry{word: s, count: 1})
}

// top returns up to n entries in rank order.
func (c *counter) top(n int) []entry {
	best := make([]entry, 0, n+1)
	for _, e := range c.entries {
		if len(best) == n && !e.less(best[n-1]) {
			continue
		}
		// Insert e at its sorted position, dropping the overflow.
		i := len(best)
		for i > 0 && e.less(best[i-1]) {
			i--
		}
		best = append(best, entry{})
		copy(best[i+1:], best[i:])
		best[i] = e
		if len(best) > n {
			best = best[:n]
		}
	}
	return best
}

// lower maps ASCII letters to their lowercase form and every other byte
// to 0, marking it as a separator.
var lower = func() (t [256]byte) {
	for b := 'a'; b <= 'z'; b++ {
		t[b] = byte(b)
		t[b-'a'+'A'] = byte(b)
	}
	return t
}()

// count reads all of r and returns the frequency of every word in it.
func count(r io.Reader) (*counter, error) {
	c := newCounter()
	buf := make([]byte, 1<<16)
	var word []byte // lowercase word in progress, possibly spanning reads
	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			if l := lower[b]; l != 0 {
				word = append(word, l)
			} else if len(word) > 0 {
				c.add(word)
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
		c.add(word)
	}
	return c, nil
}

// Run executes the wordfreq subcommand, reading from r and writing to w.
func Run(r io.Reader, w io.Writer) error {
	c, err := count(r)
	if err != nil {
		return err
	}
	for _, e := range c.top(topN) {
		if _, err := fmt.Fprintf(w, "%d %s\n", e.count, e.word); err != nil {
			return err
		}
	}
	return nil
}
