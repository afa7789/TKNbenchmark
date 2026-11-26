// Command wordfreq prints the 10 most frequent ASCII words read from standard input.
//
// A word is a maximal run of ASCII letters; every other byte is a separator.
// Words are folded to lowercase and ranked by count descending, then by word
// ascending (byte order).
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
)

const topN = 10

// wordCount is a word together with its number of occurrences.
type wordCount struct {
	word  string
	count int
}

// ranksBefore reports whether a should be listed before b.
func ranksBefore(a, b wordCount) bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// countWords lowercases ASCII letters in buf in place and counts each word.
func countWords(buf []byte) map[string]int {
	counts := make(map[string]int)
	start := -1
	for i, b := range buf {
		switch {
		case b >= 'a' && b <= 'z':
		case b >= 'A' && b <= 'Z':
			buf[i] = b | 0x20
		default:
			if start >= 0 {
				counts[string(buf[start:i])]++
				start = -1
			}
			continue
		}
		if start < 0 {
			start = i
		}
	}
	if start >= 0 {
		counts[string(buf[start:])]++
	}
	return counts
}

// topWords selects the n highest-ranked entries without sorting the whole map.
func topWords(counts map[string]int, n int) []wordCount {
	top := make([]wordCount, 0, n+1)
	for word, count := range counts {
		e := wordCount{word, count}
		if len(top) == n && !ranksBefore(e, top[n-1]) {
			continue
		}
		if len(top) < n {
			top = append(top, e)
		}
		pos := len(top) - 1
		for pos > 0 && ranksBefore(e, top[pos-1]) {
			top[pos] = top[pos-1]
			pos--
		}
		top[pos] = e
	}
	return top
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("read stdin: %w", err)
	}
	bw := bufio.NewWriter(w)
	for _, e := range topWords(countWords(input), topN) {
		bw.WriteString(strconv.Itoa(e.count))
		bw.WriteByte(' ')
		bw.WriteString(e.word)
		bw.WriteByte('\n')
	}
	return bw.Flush()
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
