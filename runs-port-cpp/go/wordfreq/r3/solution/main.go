// Command wordfreq prints the 10 most frequent ASCII-letter words read from stdin.
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

// entry is a distinct word and the number of times it occurred.
type entry struct {
	word  string
	count uint64
}

func isUpper(c byte) bool { return c >= 'A' && c <= 'Z' }
func isLower(c byte) bool { return c >= 'a' && c <= 'z' }

// countWords lowercases text in place and counts each maximal run of ASCII
// letters. Every other byte is a separator.
func countWords(text []byte) map[string]*uint64 {
	counts := make(map[string]*uint64, 1<<12)
	n := len(text)
	for i := 0; i < n; {
		for i < n && !isLower(text[i]) && !isUpper(text[i]) {
			i++
		}
		start := i
		for ; i < n; i++ {
			c := text[i]
			if isUpper(c) {
				text[i] = c + ('a' - 'A')
			} else if !isLower(c) {
				break
			}
		}
		if i == start {
			continue
		}
		word := text[start:i]
		// Lookups with string(word) do not allocate; only new words are copied.
		if p, ok := counts[string(word)]; ok {
			*p++
		} else {
			one := uint64(1)
			counts[string(word)] = &one
		}
	}
	return counts
}

// rank compares entries by count descending, then by word ascending.
func rank(a, b entry) int {
	if c := cmp.Compare(b.count, a.count); c != 0 {
		return c
	}
	return cmp.Compare(a.word, b.word)
}

// top returns the k highest-ranked entries in rank order.
func top(counts map[string]*uint64, k int) []entry {
	entries := make([]entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, entry{word: w, count: *c})
	}
	slices.SortFunc(entries, rank)
	return entries[:min(k, len(entries))]
}

func run(in io.Reader, out io.Writer) error {
	text, err := io.ReadAll(in)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	w := bufio.NewWriter(out)
	var buf []byte
	for _, e := range top(countWords(text), topN) {
		buf = strconv.AppendUint(buf[:0], e.count, 10)
		buf = append(buf, ' ')
		buf = append(buf, e.word...)
		buf = append(buf, '\n')
		if _, err := w.Write(buf); err != nil {
			return err
		}
	}
	return w.Flush()
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
