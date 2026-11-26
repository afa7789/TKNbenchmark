// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII-letter words, folded to lowercase.
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
	chunkSize = 256 << 10
)

func main() {
	counts, err := countWords(os.Stdin)
	if err != nil {
		fmt.Fprintf(os.Stderr, "wordfreq: %v\n", err)
		os.Exit(1)
	}
	if err := writeTop(os.Stdout, top(counts, topN)); err != nil {
		fmt.Fprintf(os.Stderr, "wordfreq: %v\n", err)
		os.Exit(1)
	}
}

// foldLetter returns the lowercase form of b and true if b is an ASCII letter.
func foldLetter(b byte) (byte, bool) {
	lower := b | 0x20
	return lower, lower >= 'a' && lower <= 'z'
}

// countWords tokenizes r into lowercase words and returns their counts.
// Each map value points to a counter so repeated words cost no allocation.
func countWords(r io.Reader) (map[string]*int, error) {
	counts := make(map[string]*int)
	add := func(word []byte) {
		if n, ok := counts[string(word)]; ok {
			*n++
			return
		}
		n := 1
		counts[string(word)] = &n
	}

	buf := make([]byte, chunkSize)
	var pending []byte // word fragment carried over from the previous chunk
	for {
		n, err := r.Read(buf)
		chunk := buf[:n]
		start := -1
		for i, b := range chunk {
			lower, ok := foldLetter(b)
			if ok {
				chunk[i] = lower
				if start < 0 {
					start = i
				}
				continue
			}
			switch {
			case start >= 0:
				if len(pending) > 0 {
					pending = append(pending, chunk[start:i]...)
					add(pending)
					pending = pending[:0]
				} else {
					add(chunk[start:i])
				}
				start = -1
			case len(pending) > 0:
				add(pending)
				pending = pending[:0]
			}
		}
		if start >= 0 {
			pending = append(pending, chunk[start:]...)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	if len(pending) > 0 {
		add(pending)
	}
	return counts, nil
}

type entry struct {
	word  string
	count int
}

// compareEntries orders by count descending, then word ascending (byte order).
func compareEntries(a, b entry) int {
	if c := cmp.Compare(b.count, a.count); c != 0 {
		return c
	}
	return cmp.Compare(a.word, b.word)
}

// top selects the n highest-ranked entries without sorting the whole map.
func top(counts map[string]*int, n int) []entry {
	best := make([]entry, 0, n+1)
	for word, c := range counts {
		e := entry{word, *c}
		if len(best) == n && compareEntries(e, best[n-1]) >= 0 {
			continue
		}
		pos, _ := slices.BinarySearchFunc(best, e, compareEntries)
		best = slices.Insert(best, pos, e)
		if len(best) > n {
			best = best[:n]
		}
	}
	return best
}

func writeTop(w io.Writer, entries []entry) error {
	bw := bufio.NewWriter(w)
	for _, e := range entries {
		bw.WriteString(strconv.Itoa(e.count))
		bw.WriteByte(' ')
		bw.WriteString(e.word)
		bw.WriteByte('\n')
	}
	return bw.Flush()
}
