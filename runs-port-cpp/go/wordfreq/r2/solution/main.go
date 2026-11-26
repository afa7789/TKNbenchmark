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

const (
	topN      = 10
	chunkSize = 1 << 16
)

// entry is a word together with its number of occurrences.
type entry struct {
	word  string
	count uint64
}

func isASCIILetter(c byte) bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

func toLowerASCII(c byte) byte {
	if c >= 'A' && c <= 'Z' {
		return c + ('a' - 'A')
	}
	return c
}

// addWord increments the count for word. The lookup via string(word) does not
// allocate; a new string is only created the first time a word is seen.
func addWord(counts map[string]uint64, word []byte) {
	if n, ok := counts[string(word)]; ok {
		counts[string(word)] = n + 1
		return
	}
	counts[string(word)] = 1
}

// countWords streams r, accumulating lowercase words. A word may straddle
// chunk boundaries, so the in-progress word is carried across reads.
func countWords(r io.Reader) (map[string]uint64, error) {
	counts := make(map[string]uint64)
	buf := make([]byte, chunkSize)
	current := make([]byte, 0, 64)

	for {
		n, err := r.Read(buf)
		for _, c := range buf[:n] {
			if isASCIILetter(c) {
				current = append(current, toLowerASCII(c))
			} else if len(current) > 0 {
				addWord(counts, current)
				current = current[:0]
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	if len(current) > 0 {
		addWord(counts, current)
	}
	return counts, nil
}

// topWords returns up to limit entries ordered by count descending, then by
// word ascending.
func topWords(counts map[string]uint64, limit int) []entry {
	entries := make([]entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, entry{word: w, count: c})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if a.count != b.count {
			return cmp.Compare(b.count, a.count)
		}
		return cmp.Compare(a.word, b.word)
	})
	return entries[:min(limit, len(entries))]
}

func run(in io.Reader, out io.Writer) error {
	counts, err := countWords(in)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	w := bufio.NewWriter(out)
	for _, e := range topWords(counts, topN) {
		w.WriteString(strconv.FormatUint(e.count, 10))
		w.WriteByte(' ')
		w.WriteString(e.word)
		w.WriteByte('\n')
	}
	return w.Flush()
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
