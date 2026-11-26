package wordfreq

import (
	"errors"
	"fmt"
	"io"
	"slices"
)

// topN is the maximum number of words reported.
const topN = 10

// lower maps every ASCII letter to its lowercase form and every other byte
// to 0, which marks it as a word separator.
var lower = func() (t [256]byte) {
	for c := byte('a'); c <= 'z'; c++ {
		t[c] = c
		t[c-'a'+'A'] = c
	}
	return t
}()

// entry is a word together with its number of occurrences.
type entry struct {
	word  string
	count int
}

// compare orders entries by count descending, then by word ascending.
func compare(a, b entry) int {
	switch {
	case a.count > b.count:
		return -1
	case a.count < b.count:
		return 1
	case a.word < b.word:
		return -1
	case a.word > b.word:
		return 1
	}
	return 0
}

// Run executes the wordfreq subcommand, reading from r and writing to w.
func Run(r io.Reader, w io.Writer) error {
	counts, err := count(r)
	if err != nil {
		return err
	}
	for _, e := range top(counts, topN) {
		if _, err := fmt.Fprintf(w, "%d %s\n", e.count, e.word); err != nil {
			return err
		}
	}
	return nil
}

// count reads all of r and returns the number of occurrences of each word,
// folded to lowercase. A word is a maximal run of ASCII letters; every other
// byte is a separator.
//
// Counters are stored behind pointers so that incrementing a known word only
// needs a map lookup, which the compiler performs without allocating a
// string from the byte slice.
func count(r io.Reader) (map[string]*int, error) {
	counts := make(map[string]*int)
	add := func(word []byte) {
		if p, ok := counts[string(word)]; ok {
			*p++
			return
		}
		n := 1
		counts[string(word)] = &n
	}

	buf := make([]byte, 256<<10)
	var word []byte // current word; it may span several reads
	for {
		n, err := r.Read(buf)
		for _, c := range buf[:n] {
			if l := lower[c]; l != 0 {
				word = append(word, l)
			} else if len(word) > 0 {
				add(word)
				word = word[:0]
			}
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	if len(word) > 0 {
		add(word)
	}
	return counts, nil
}

// top returns at most n entries of counts in ranking order.
func top(counts map[string]*int, n int) []entry {
	if n <= 0 {
		return nil
	}
	best := make([]entry, 0, n+1)
	for w, p := range counts {
		e := entry{word: w, count: *p}
		if len(best) == n && compare(e, best[n-1]) >= 0 {
			continue
		}
		i, _ := slices.BinarySearchFunc(best, e, compare)
		best = slices.Insert(best, i, e)
		if len(best) > n {
			best = best[:n]
		}
	}
	return best
}
