// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII words, case-folded, ordered by count descending then word ascending.
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

// lower maps ASCII letters to their lowercase form and every other byte to 0.
var lower = func() (t [256]byte) {
	for c := 'a'; c <= 'z'; c++ {
		t[c] = byte(c)
		t[c-'a'+'A'] = byte(c)
	}
	return t
}()

type entry struct {
	word  string
	count int
}

// counter accumulates word frequencies.
type counter struct {
	index   map[string]int // word -> position in entries
	entries []entry
}

func newCounter() *counter {
	return &counter{index: make(map[string]int)}
}

// add records one occurrence of w. The lookup does not allocate; the key is
// copied only the first time a word is seen.
func (c *counter) add(w []byte) {
	if i, ok := c.index[string(w)]; ok {
		c.entries[i].count++
		return
	}
	s := string(w)
	c.index[s] = len(c.entries)
	c.entries = append(c.entries, entry{word: s, count: 1})
}

// count scans r and returns the frequency of every word in it. Words may
// span read boundaries.
func count(r io.Reader) (*counter, error) {
	c := newCounter()
	buf := make([]byte, 1<<16)
	word := make([]byte, 0, 64)
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
		if err == io.EOF {
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

func compareEntries(a, b entry) int {
	if n := cmp.Compare(b.count, a.count); n != 0 {
		return n
	}
	return cmp.Compare(a.word, b.word)
}

// top returns the n highest-ranked entries.
func (c *counter) top(n int) []entry {
	es := c.entries
	slices.SortFunc(es, compareEntries)
	return es[:min(n, len(es))]
}

func run() error {
	c, err := count(os.Stdin)
	if err != nil {
		return fmt.Errorf("read stdin: %w", err)
	}
	w := bufio.NewWriter(os.Stdout)
	var line []byte
	for _, e := range c.top(topN) {
		line = strconv.AppendInt(line[:0], int64(e.count), 10)
		line = append(line, ' ')
		line = append(line, e.word...)
		line = append(line, '\n')
		if _, err := w.Write(line); err != nil {
			return fmt.Errorf("write stdout: %w", err)
		}
	}
	if err := w.Flush(); err != nil {
		return fmt.Errorf("write stdout: %w", err)
	}
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
