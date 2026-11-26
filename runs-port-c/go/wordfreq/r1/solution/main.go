// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII-letter words (case-folded), ordered by count descending, then by
// word ascending.
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
	readChunk = 1 << 16
)

// WordCount is a word together with the number of times it occurred.
type WordCount struct {
	Word  string
	Count int
}

func isLetter(c byte) bool {
	return (c|0x20)-'a' < 26
}

// CountWords tallies the case-folded words in r. A word is a maximal run of
// ASCII letters; every other byte is a separator.
func CountWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int)
	buf := make([]byte, readChunk)
	var pending []byte // a word that may continue into the next chunk

	for {
		n, err := r.Read(buf)
		chunk := buf[:n]
		i := 0
		for i < len(chunk) {
			if !isLetter(chunk[i]) {
				if len(pending) > 0 {
					counts[string(pending)]++
					pending = pending[:0]
				}
				i++
				continue
			}
			start := i
			for i < len(chunk) && isLetter(chunk[i]) {
				chunk[i] |= 0x20
				i++
			}
			word := chunk[start:i]
			switch {
			case len(pending) == 0 && i < len(chunk):
				// Fast path: the word lies entirely within this chunk.
				// The string conversion in the map index does not allocate.
				counts[string(word)]++
			case i < len(chunk):
				pending = append(pending, word...)
				counts[string(pending)]++
				pending = pending[:0]
			default:
				pending = append(pending, word...)
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	if len(pending) > 0 {
		counts[string(pending)]++
	}
	return counts, nil
}

// compareRank orders by count descending, then by word ascending.
func compareRank(a, b WordCount) int {
	if c := cmp.Compare(b.Count, a.Count); c != 0 {
		return c
	}
	return cmp.Compare(a.Word, b.Word)
}

// Top returns up to n entries of counts in rank order.
func Top(counts map[string]int, n int) []WordCount {
	top := make([]WordCount, 0, n+1)
	for w, c := range counts {
		e := WordCount{Word: w, Count: c}
		if len(top) == n && compareRank(e, top[n-1]) >= 0 {
			continue
		}
		pos, _ := slices.BinarySearchFunc(top, e, compareRank)
		top = slices.Insert(top, pos, e)
		if len(top) > n {
			top = top[:n]
		}
	}
	return top
}

func run(in io.Reader, out io.Writer) error {
	counts, err := CountWords(in)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	w := bufio.NewWriter(out)
	for _, e := range Top(counts, topN) {
		w.WriteString(strconv.Itoa(e.Count))
		w.WriteByte(' ')
		w.WriteString(e.Word)
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
