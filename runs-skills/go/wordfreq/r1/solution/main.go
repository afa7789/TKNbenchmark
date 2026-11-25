// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII words, case-insensitively, as "<count> <word>" lines.
package main

import (
	"bufio"
	"cmp"
	"fmt"
	"io"
	"os"
	"slices"
)

const topN = 10

// entry is a word together with its number of occurrences.
type entry struct {
	word  string
	count int
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	counts, err := countWords(r)
	if err != nil {
		return fmt.Errorf("read input: %w", err)
	}
	bw := bufio.NewWriter(w)
	for _, e := range top(counts, topN) {
		fmt.Fprintf(bw, "%d %s\n", e.count, e.word)
	}
	return bw.Flush()
}

// countWords counts maximal runs of ASCII letters in r, folded to lowercase.
// Every other byte is a separator. Input is streamed, so words may span
// read boundaries.
func countWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, 64*1024)
	word := make([]byte, 0, 64)
	for {
		n, err := r.Read(buf)
		for _, c := range buf[:n] {
			switch {
			case 'a' <= c && c <= 'z':
				word = append(word, c)
			case 'A' <= c && c <= 'Z':
				word = append(word, c+('a'-'A'))
			case len(word) > 0:
				counts[string(word)]++ // no allocation for existing keys
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
		counts[string(word)]++
	}
	return counts, nil
}

// top returns up to n entries ordered by count descending, then word ascending.
func top(counts map[string]int, n int) []entry {
	entries := make([]entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, entry{word: w, count: c})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if c := cmp.Compare(b.count, a.count); c != 0 {
			return c
		}
		return cmp.Compare(a.word, b.word)
	})
	return entries[:min(n, len(entries))]
}
