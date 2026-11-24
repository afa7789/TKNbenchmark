// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII words, case-insensitively, as "<count> <word>" lines.
package main

import (
	"bufio"
	"cmp"
	"errors"
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

// countWords tallies lowercase ASCII-letter runs read from r.
func countWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, 256*1024)
	var word []byte
	for {
		n, err := r.Read(buf)
		for _, c := range buf[:n] {
			switch {
			case c >= 'a' && c <= 'z':
				word = append(word, c)
			case c >= 'A' && c <= 'Z':
				word = append(word, c+('a'-'A'))
			case len(word) > 0:
				counts[string(word)]++ // map lookup with string(b) does not allocate
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
		entries = append(entries, entry{w, c})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if a.count != b.count {
			return cmp.Compare(b.count, a.count)
		}
		return cmp.Compare(a.word, b.word)
	})
	return entries[:min(n, len(entries))]
}

func run(r io.Reader, w io.Writer) error {
	counts, err := countWords(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	bw := bufio.NewWriter(w)
	var line []byte
	for _, e := range top(counts, topN) {
		line = strconv.AppendInt(line[:0], int64(e.count), 10)
		line = append(line, ' ')
		line = append(line, e.word...)
		line = append(line, '\n')
		if _, err := bw.Write(line); err != nil {
			return err
		}
	}
	return bw.Flush()
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil && !errors.Is(err, io.EOF) {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
