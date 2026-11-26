// Command wordfreq prints the 10 most frequent ASCII words read from standard input.
//
// A word is a maximal run of ASCII letters; every other byte is a separator.
// Words are folded to lowercase and printed as "<count> <word>", ordered by
// count descending and then by word ascending.
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

// wordCount is a distinct word together with its number of occurrences.
type wordCount struct {
	word  string
	count int
}

// isLetter reports whether b is an ASCII letter.
func isLetter(b byte) bool {
	return (b|0x20) >= 'a' && (b|0x20) <= 'z'
}

// countWords reads r to EOF and returns the occurrence count of every
// lowercase-folded word.
func countWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, 1<<16)
	word := make([]byte, 0, 64) // current word, possibly spanning reads

	flush := func() {
		if len(word) > 0 {
			counts[string(word)]++ // lookup via string(word) does not allocate
			word = word[:0]
		}
	}

	for {
		n, err := r.Read(buf)
		for _, b := range buf[:n] {
			if isLetter(b) {
				word = append(word, b|0x20)
			} else {
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

// topWords returns up to n entries of counts, by count descending then word ascending.
func topWords(counts map[string]int, n int) []wordCount {
	all := make([]wordCount, 0, len(counts))
	for w, c := range counts {
		all = append(all, wordCount{w, c})
	}
	slices.SortFunc(all, func(a, b wordCount) int {
		if c := cmp.Compare(b.count, a.count); c != 0 {
			return c
		}
		return cmp.Compare(a.word, b.word)
	})
	return all[:min(n, len(all))]
}

func run() error {
	counts, err := countWords(os.Stdin)
	if err != nil {
		return fmt.Errorf("reading stdin: %w", err)
	}

	out := bufio.NewWriter(os.Stdout)
	var line []byte
	for _, wc := range topWords(counts, topN) {
		line = strconv.AppendInt(line[:0], int64(wc.count), 10)
		line = append(line, ' ')
		line = append(line, wc.word...)
		line = append(line, '\n')
		if _, err := out.Write(line); err != nil {
			return fmt.Errorf("writing stdout: %w", err)
		}
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing stdout: %w", err)
	}
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
