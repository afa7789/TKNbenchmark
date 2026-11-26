// Package wordfreq prints the most frequent words of its input.
//
// See the wordfreq section of SPEC.md for the exact input and output formats.
package wordfreq

import (
	"errors"
	"io"
	"strconv"
)

// topN is the maximum number of words printed.
const topN = 10

// readBufSize is the size of the chunks read from the input.
const readBufSize = 256 << 10

// lower maps every byte to its lowercase ASCII letter, or to 0 if the byte
// is not an ASCII letter (and therefore a word separator).
var lower = func() (t [256]byte) {
	for c := 'a'; c <= 'z'; c++ {
		t[c] = byte(c)
		t[c-'a'+'A'] = byte(c)
	}
	return t
}()

// entry is a distinct word and the number of times it occurs.
type entry struct {
	word  string
	count int
}

// before reports whether a ranks ahead of b: higher count first, ties broken
// by word in ascending byte order.
func (a entry) before(b entry) bool {
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

// add records one occurrence of the lowercase word w. w is not retained.
func (c *counter) add(w []byte) {
	// The string(w) conversion in a map lookup does not allocate.
	if i, ok := c.index[string(w)]; ok {
		c.entries[i].count++
		return
	}
	s := string(w)
	c.index[s] = len(c.entries)
	c.entries = append(c.entries, entry{word: s, count: 1})
}

// top returns up to n entries in rank order.
func (c *counter) top(n int) []entry {
	best := make([]entry, 0, n+1)
	for _, e := range c.entries {
		if len(best) == n && !e.before(best[n-1]) {
			continue
		}
		// Insert e into its sorted position, dropping the last entry if full.
		i := len(best)
		for i > 0 && e.before(best[i-1]) {
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

// Run reads the whole wordfreq input from r and writes the results to w.
// w is buffered by the caller, which flushes it after Run returns.
func Run(r io.Reader, w io.Writer) error {
	c := newCounter()
	buf := make([]byte, readBufSize)
	var word []byte // the current word, lowercased; may span reads

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
			return err
		}
	}
	if len(word) > 0 {
		c.add(word)
	}

	return writeTop(w, c.top(topN))
}

// writeTop writes each entry as a "<count> <word>" line.
func writeTop(w io.Writer, entries []entry) error {
	var out []byte
	for _, e := range entries {
		out = strconv.AppendInt(out, int64(e.count), 10)
		out = append(out, ' ')
		out = append(out, e.word...)
		out = append(out, '\n')
	}
	_, err := w.Write(out)
	return err
}
