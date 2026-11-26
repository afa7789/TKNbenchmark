// Command wordfreq reads standard input and prints the 10 most frequent
// words, where a word is a maximal run of ASCII letters folded to lowercase.
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

// entry is a word together with its number of occurrences.
type entry struct {
	word  string
	count int
}

func isLetter(b byte) bool {
	return ('a' <= b && b <= 'z') || ('A' <= b && b <= 'Z')
}

// countWords counts case-folded words in data. data is lowercased in place.
func countWords(data []byte) map[string]int {
	counts := make(map[string]int)
	i, n := 0, len(data)
	for i < n {
		for i < n && !isLetter(data[i]) {
			i++
		}
		if i >= n {
			break
		}
		start := i
		for ; i < n; i++ {
			b := data[i]
			if 'A' <= b && b <= 'Z' {
				data[i] = b | 0x20
			} else if b < 'a' || b > 'z' {
				break
			}
		}
		// The compiler avoids allocating for the string conversion when the
		// key already exists in the map.
		counts[string(data[start:i])]++
	}
	return counts
}

// compareEntries orders by count descending, then word ascending.
func compareEntries(a, b entry) int {
	if c := cmp.Compare(b.count, a.count); c != 0 {
		return c
	}
	return cmp.Compare(a.word, b.word)
}

// topWords returns the n best entries in order, without sorting the whole map.
func topWords(counts map[string]int, n int) []entry {
	if n <= 0 {
		return nil
	}
	top := make([]entry, 0, n)
	for word, count := range counts {
		e := entry{word, count}
		if len(top) == n && compareEntries(e, top[n-1]) >= 0 {
			continue
		}
		pos, _ := slices.BinarySearchFunc(top, e, compareEntries)
		if len(top) < n {
			top = slices.Insert(top, pos, e)
		} else {
			copy(top[pos+1:], top[pos:n-1])
			top[pos] = e
		}
	}
	return top
}

func run(r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	bw := bufio.NewWriter(w)
	var buf []byte
	for _, e := range topWords(countWords(data), topN) {
		buf = strconv.AppendInt(buf[:0], int64(e.count), 10)
		buf = append(buf, ' ')
		buf = append(buf, e.word...)
		buf = append(buf, '\n')
		if _, err := bw.Write(buf); err != nil {
			return fmt.Errorf("writing output: %w", err)
		}
	}
	if err := bw.Flush(); err != nil {
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
