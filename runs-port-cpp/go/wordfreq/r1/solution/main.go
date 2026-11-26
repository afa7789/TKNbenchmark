// Command wordfreq prints the 10 most frequent ASCII-letter words read from stdin.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"slices"
	"strconv"
	"strings"
)

const (
	topN      = 10
	chunkSize = 1 << 16
)

// wordCounter tokenizes a byte stream into lowercase words, tolerating words
// split across chunk boundaries.
type wordCounter struct {
	counts  map[string]uint64
	current []byte
}

func newWordCounter() *wordCounter {
	return &wordCounter{counts: make(map[string]uint64)}
}

func isASCIILetter(c byte) bool {
	return ('A' <= c && c <= 'Z') || ('a' <= c && c <= 'z')
}

// feed consumes the next chunk of input.
func (wc *wordCounter) feed(chunk []byte) {
	start := -1 // start of a word lying entirely within chunk, or -1
	for i, c := range chunk {
		if isASCIILetter(c) {
			if start < 0 && len(wc.current) == 0 {
				start = i
			}
			continue
		}
		if start >= 0 {
			wc.add(chunk[start:i])
			start = -1
		} else if len(wc.current) > 0 {
			wc.flushCarry(chunk[:i])
		}
	}
	// Carry an unterminated trailing word over to the next chunk.
	switch {
	case start >= 0:
		wc.current = append(wc.current, chunk[start:]...)
	case len(wc.current) > 0:
		wc.current = append(wc.current, chunk...)
	}
}

// flushCarry completes the word carried over from the previous chunk with
// the given prefix of the current chunk.
func (wc *wordCounter) flushCarry(prefix []byte) {
	wc.current = append(wc.current, prefix...)
	wc.add(wc.current)
	wc.current = wc.current[:0]
}

// finish flushes any word still pending at end of input.
func (wc *wordCounter) finish() {
	if len(wc.current) > 0 {
		wc.add(wc.current)
		wc.current = wc.current[:0]
	}
}

// add counts word, lowercasing it first. word may be modified in place.
func (wc *wordCounter) add(word []byte) {
	for i, c := range word {
		word[i] = c | 0x20 // valid only because word holds ASCII letters
	}
	// The compiler elides the allocation for map[string(b)] lookups.
	if n, ok := wc.counts[string(word)]; ok {
		wc.counts[string(word)] = n + 1
		return
	}
	wc.counts[string(word)] = 1
}

type entry struct {
	word  string
	count uint64
}

// topWords returns up to n entries ordered by count descending, then word ascending.
func topWords(counts map[string]uint64, n int) []entry {
	entries := make([]entry, 0, len(counts))
	for w, c := range counts {
		entries = append(entries, entry{w, c})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if a.count != b.count {
			if a.count > b.count {
				return -1
			}
			return 1
		}
		return strings.Compare(a.word, b.word)
	})
	return entries[:min(n, len(entries))]
}

func run(r io.Reader, w io.Writer) error {
	wc := newWordCounter()
	buf := make([]byte, chunkSize)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			wc.feed(buf[:n])
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	wc.finish()

	out := bufio.NewWriter(w)
	for _, e := range topWords(wc.counts, topN) {
		out.WriteString(strconv.FormatUint(e.count, 10))
		out.WriteByte(' ')
		out.WriteString(e.word)
		out.WriteByte('\n')
	}
	return out.Flush()
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
	}
}
