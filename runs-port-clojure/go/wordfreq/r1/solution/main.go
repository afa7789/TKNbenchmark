// Command wordfreq reads standard input and prints the ten most frequent
// ASCII words, one "<count> <word>" line each.
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

// wordCount pairs a lowercased word with its number of occurrences.
type wordCount struct {
	word  string
	count int
}

// countWords returns the occurrence count of every word in buf. A word is a
// maximal run of ASCII letters, folded to lowercase.
func countWords(buf []byte) map[string]int {
	counts := make(map[string]int)
	word := make([]byte, 0, 64)
	flush := func() {
		if len(word) > 0 {
			counts[string(word)]++ // no allocation when the key already exists
			word = word[:0]
		}
	}
	for _, b := range buf {
		switch {
		case 'a' <= b && b <= 'z':
			word = append(word, b)
		case 'A' <= b && b <= 'Z':
			word = append(word, b+('a'-'A'))
		default:
			flush()
		}
	}
	flush()
	return counts
}

// topWords returns up to n entries ordered by count descending, then word
// ascending in byte order.
func topWords(counts map[string]int, n int) []wordCount {
	entries := make([]wordCount, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, wordCount{w, c})
	}
	slices.SortFunc(entries, func(a, b wordCount) int {
		if c := cmp.Compare(b.count, a.count); c != 0 {
			return c
		}
		return cmp.Compare(a.word, b.word)
	})
	return entries[:min(n, len(entries))]
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	out := bufio.NewWriter(w)
	var line []byte
	for _, e := range topWords(countWords(input), topN) {
		line = strconv.AppendInt(line[:0], int64(e.count), 10)
		line = append(line, ' ')
		line = append(line, e.word...)
		line = append(line, '\n')
		if _, err := out.Write(line); err != nil {
			return fmt.Errorf("writing output: %w", err)
		}
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
