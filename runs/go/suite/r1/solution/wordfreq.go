package main

import (
	"bufio"
	"cmp"
	"io"
	"strconv"
)

const topN = 10

type wordCount struct {
	word  string
	count int
}

// before reports whether a ranks ahead of b: higher count first, then
// lexicographically smaller word.
func (a wordCount) before(b wordCount) bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return cmp.Less(a.word, b.word)
}

// wordFreq prints the topN most frequent case-folded ASCII-letter words of r.
func wordFreq(r io.Reader, w *bufio.Writer) error {
	counts := make(map[string]*int)
	buf := make([]byte, 256*1024)
	word := make([]byte, 0, 64) // current (possibly chunk-spanning) word, lowercased

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
			break
		}
		if err != nil {
			return err
		}
	}
	flush()

	for _, e := range topWords(counts, topN) {
		w.WriteString(strconv.Itoa(e.count))
		w.WriteByte(' ')
		w.WriteString(e.word)
		w.WriteByte('\n')
	}
	return nil
}

// topWords returns up to n entries of counts in rank order, in O(len(counts)*n).
func topWords(counts map[string]*int, n int) []wordCount {
	top := make([]wordCount, 0, n+1)
	for word, p := range counts {
		e := wordCount{word, *p}
		if len(top) == n && !e.before(top[n-1]) {
			continue
		}
		i := len(top)
		for i > 0 && e.before(top[i-1]) {
			i--
		}
		top = append(top, wordCount{})
		copy(top[i+1:], top[i:])
		top[i] = e
		if len(top) > n {
			top = top[:n]
		}
	}
	return top
}
