// Command wordfreq prints the 10 most frequent ASCII words read from standard input.
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

// wordCount is a lowercase word together with its number of occurrences.
type wordCount struct {
	word  string
	count int
}

// lower returns the lowercase form of an ASCII letter and true,
// or 0 and false for any separator byte.
func lower(b byte) (byte, bool) {
	switch {
	case 'a' <= b && b <= 'z':
		return b, true
	case 'A' <= b && b <= 'Z':
		return b + ('a' - 'A'), true
	default:
		return 0, false
	}
}

// countWords reads r to exhaustion and returns lowercase word -> count.
func countWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, 1<<16)
	word := make([]byte, 0, 64)

	flush := func() {
		if len(word) > 0 {
			// The compiler avoids allocating for the string(word) lookup key.
			counts[string(word)]++
			word = word[:0]
		}
	}

	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			if lc, ok := lower(b); ok {
				word = append(word, lc)
			} else {
				flush()
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	flush()
	return counts, nil
}

// topWords returns up to n entries ordered by count descending, then word ascending.
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

func run() error {
	counts, err := countWords(os.Stdin)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	out := bufio.NewWriter(os.Stdout)
	for _, e := range topWords(counts, topN) {
		out.WriteString(strconv.Itoa(e.count))
		out.WriteByte(' ')
		out.WriteString(e.word)
		out.WriteByte('\n')
	}
	return out.Flush()
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
	}
}
