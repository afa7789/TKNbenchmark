// Command wordfreq reads standard input and prints the 10 most frequent
// words, where a word is a maximal run of ASCII letters, case-folded.
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

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
	}
}

func run(r io.Reader, w io.Writer) error {
	counts, err := countWords(r)
	if err != nil {
		return fmt.Errorf("read input: %w", err)
	}
	bw := bufio.NewWriter(w)
	for _, e := range top(counts, topN) {
		bw.WriteString(strconv.Itoa(e.count))
		bw.WriteByte(' ')
		bw.WriteString(e.word)
		bw.WriteByte('\n')
	}
	return bw.Flush()
}

// countWords tallies lowercase ASCII-letter words read from r. Words may span
// read boundaries; the partial word is carried in a reusable buffer.
func countWords(r io.Reader) (map[string]*int, error) {
	counts := make(map[string]*int)
	buf := make([]byte, 256*1024)
	word := make([]byte, 0, 64)

	flush := func() {
		if len(word) == 0 {
			return
		}
		// The string(word) conversion in a map lookup does not allocate.
		if p := counts[string(word)]; p != nil {
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
			case 'a' <= c && c <= 'z':
				word = append(word, c)
			case 'A' <= c && c <= 'Z':
				word = append(word, c+('a'-'A'))
			default:
				flush()
			}
		}
		if err == io.EOF {
			flush()
			return counts, nil
		}
		if err != nil {
			return nil, err
		}
	}
}

// top returns up to n entries ordered by count descending, then word ascending.
func top(counts map[string]*int, n int) []entry {
	entries := make([]entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, entry{w, *c})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if c := cmp.Compare(b.count, a.count); c != 0 {
			return c
		}
		return cmp.Compare(a.word, b.word)
	})
	return entries[:min(n, len(entries))]
}
