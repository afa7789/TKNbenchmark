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

// less reports whether a ranks before b: higher count first, then word ascending.
func less(a, b entry) int {
	if c := cmp.Compare(b.count, a.count); c != 0 {
		return c
	}
	return cmp.Compare(a.word, b.word)
}

// countWords tokenizes r and returns the occurrence count of each lowercase word.
func countWords(r io.Reader) (map[string]*int, error) {
	counts := make(map[string]*int)
	buf := make([]byte, 256*1024)
	word := make([]byte, 0, 64)

	flush := func() {
		if p, ok := counts[string(word)]; ok {
			*p++
		} else {
			n := 1
			counts[string(word)] = &n
		}
		word = word[:0]
	}

	for {
		n, err := r.Read(buf)
		for _, c := range buf[:n] {
			switch {
			case c >= 'a' && c <= 'z':
				word = append(word, c)
			case c >= 'A' && c <= 'Z':
				word = append(word, c+('a'-'A'))
			case len(word) > 0:
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
	if len(word) > 0 {
		flush()
	}
	return counts, nil
}

// top returns the n highest-ranked entries in counts, in rank order.
func top(counts map[string]*int, n int) []entry {
	best := make([]entry, 0, n+1)
	for w, p := range counts {
		e := entry{w, *p}
		if len(best) == n && less(e, best[n-1]) >= 0 {
			continue
		}
		i, _ := slices.BinarySearchFunc(best, e, less)
		best = slices.Insert(best, i, e)
		if len(best) > n {
			best = best[:n]
		}
	}
	return best
}

func run() error {
	counts, err := countWords(os.Stdin)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	out := bufio.NewWriter(os.Stdout)
	for _, e := range top(counts, topN) {
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
		os.Exit(1)
	}
}
