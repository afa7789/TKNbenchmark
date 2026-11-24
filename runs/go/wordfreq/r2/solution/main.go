// Command wordfreq reads standard input and prints the 10 most frequent
// words, where a word is a maximal run of ASCII letters, case-folded to
// lowercase.
package main

import (
	"bufio"
	"cmp"
	"fmt"
	"io"
	"os"
	"slices"
	"strconv"
)

const topN = 10

type entry struct {
	word  string
	count int
}

// counter accumulates case-folded word frequencies from a byte stream.
type counter struct {
	counts map[string]*int
	word   []byte // word in progress, possibly spanning read boundaries
}

func newCounter() *counter {
	return &counter{counts: make(map[string]*int), word: make([]byte, 0, 64)}
}

// Write implements io.Writer so a counter can be fed with io.Copy.
func (c *counter) Write(p []byte) (int, error) {
	for _, b := range p {
		switch {
		case 'a' <= b && b <= 'z':
			c.word = append(c.word, b)
		case 'A' <= b && b <= 'Z':
			c.word = append(c.word, b+('a'-'A'))
		default:
			c.flush()
		}
	}
	return len(p), nil
}

// flush records the word in progress, if any.
func (c *counter) flush() {
	if len(c.word) == 0 {
		return
	}
	// The string(c.word) conversion in a map index does not allocate.
	if n, ok := c.counts[string(c.word)]; ok {
		*n++
	} else {
		one := 1
		c.counts[string(c.word)] = &one
	}
	c.word = c.word[:0]
}

// top returns up to n entries ordered by count descending, then word ascending.
func (c *counter) top(n int) []entry {
	c.flush()
	entries := make([]entry, 0, len(c.counts))
	for w, cnt := range c.counts {
		entries = append(entries, entry{word: w, count: *cnt})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if r := cmp.Compare(b.count, a.count); r != 0 {
			return r
		}
		return cmp.Compare(a.word, b.word)
	})
	return entries[:min(n, len(entries))]
}

func run(r io.Reader, w io.Writer) error {
	c := newCounter()
	if _, err := io.CopyBuffer(c, r, make([]byte, 256*1024)); err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	bw := bufio.NewWriter(w)
	var line []byte
	for _, e := range c.top(topN) {
		line = strconv.AppendInt(line[:0], int64(e.count), 10)
		line = append(line, ' ')
		line = append(line, e.word...)
		line = append(line, '\n')
		if _, err := bw.Write(line); err != nil {
			return fmt.Errorf("writing output: %w", err)
		}
	}
	if err := bw.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
	}
}
