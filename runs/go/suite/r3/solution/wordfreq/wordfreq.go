// Package wordfreq counts case-insensitive ASCII words and reports the most frequent ones.
package wordfreq

import (
	"cmp"
	"errors"
	"io"
	"slices"
	"strconv"
)

// lower maps ASCII letters to their lowercase form and every other byte to 0.
var lower = func() (t [256]byte) {
	for c := 'a'; c <= 'z'; c++ {
		t[c] = byte(c)
		t[c-'a'+'A'] = byte(c)
	}
	return t
}()

// Entry is a word together with its number of occurrences.
type Entry struct {
	Word  string
	Count int
}

// Count reads r to EOF and returns the occurrence count of every word.
// A word is a maximal run of ASCII letters, folded to lowercase.
func Count(r io.Reader) (map[string]int, error) {
	counts := make(map[string]*int)
	buf := make([]byte, 1<<20)
	var word []byte // current (possibly partial) lowercase word

	flush := func() {
		if len(word) == 0 {
			return
		}
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
			if l := lower[c]; l != 0 {
				word = append(word, l)
			} else {
				flush()
			}
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	flush()

	result := make(map[string]int, len(counts))
	for w, p := range counts {
		result[w] = *p
	}
	return result, nil
}

// Top returns up to n entries ordered by count descending, then word ascending.
func Top(counts map[string]int, n int) []Entry {
	entries := make([]Entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, Entry{w, c})
	}
	slices.SortFunc(entries, func(a, b Entry) int {
		if c := cmp.Compare(b.Count, a.Count); c != 0 {
			return c
		}
		return cmp.Compare(a.Word, b.Word)
	})
	return entries[:min(n, len(entries))]
}

// Run writes the n most frequent words of r to w, one "<count> <word>" per line.
func Run(r io.Reader, w io.Writer, n int) error {
	counts, err := Count(r)
	if err != nil {
		return err
	}
	var line []byte
	for _, e := range Top(counts, n) {
		line = strconv.AppendInt(line[:0], int64(e.Count), 10)
		line = append(line, ' ')
		line = append(line, e.Word...)
		line = append(line, '\n')
		if _, err := w.Write(line); err != nil {
			return err
		}
	}
	return nil
}
