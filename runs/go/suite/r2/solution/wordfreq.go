package main

import (
	"bufio"
	"io"
	"strconv"
)

// topN is the number of words wordFreq reports.
const topN = 10

type wordCount struct {
	word  string
	count int
}

// before reports whether a ranks ahead of b: higher count first, then word ascending.
func (a wordCount) before(b wordCount) bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// wordFreq prints the topN most frequent case-folded ASCII-letter words in r.
func wordFreq(r io.Reader, w *bufio.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}

	counts := make(map[string]*int)
	for i := 0; i < len(data); {
		if !isLetter(data[i]) {
			i++
			continue
		}
		start := i
		for ; i < len(data) && isLetter(data[i]); i++ {
			data[i] |= 0x20 // ASCII lowercase
		}
		word := data[start:i]
		if p, ok := counts[string(word)]; ok {
			*p++
		} else {
			n := 1
			counts[string(word)] = &n
		}
	}

	for _, wc := range top(counts, topN) {
		w.WriteString(strconv.Itoa(wc.count))
		w.WriteByte(' ')
		w.WriteString(wc.word)
		w.WriteByte('\n')
	}
	return nil
}

// top returns the n highest-ranked entries of counts, in rank order.
func top(counts map[string]*int, n int) []wordCount {
	best := make([]wordCount, 0, n+1)
	for word, p := range counts {
		wc := wordCount{word, *p}
		if len(best) == n && !wc.before(best[n-1]) {
			continue
		}
		// Insertion into a small sorted slice.
		j := len(best)
		best = append(best, wc)
		for ; j > 0 && wc.before(best[j-1]); j-- {
			best[j] = best[j-1]
		}
		best[j] = wc
		if len(best) > n {
			best = best[:n]
		}
	}
	return best
}

func isLetter(c byte) bool {
	return (c|0x20) >= 'a' && (c|0x20) <= 'z'
}
