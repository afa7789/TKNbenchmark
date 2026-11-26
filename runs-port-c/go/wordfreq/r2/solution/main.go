// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII words.
//
// A word is a maximal run of ASCII letters, folded to lowercase. Output is
// "<count> <word>" per line, ordered by count descending, then word ascending
// (byte order), at most 10 lines.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

const topN = 10

func main() {
	counts, err := countWords(os.Stdin)
	if err != nil {
		// Report the failure but still print what was read, as the
		// original implementation does.
		fmt.Fprintf(os.Stderr, "wordfreq: read error: %v\n", err)
	}

	w := bufio.NewWriter(os.Stdout)
	for _, e := range top(counts, topN) {
		fmt.Fprintf(w, "%d %s\n", e.count, e.word)
	}
	if err := w.Flush(); err != nil {
		os.Exit(1)
	}
}

// readChunk is the size of each read from the input.
const readChunk = 1 << 16

// countWords counts the lowercase-folded ASCII words in r. On a read error
// it returns the counts gathered so far along with the error.
func countWords(r io.Reader) (map[string]int, error) {
	counts := make(map[string]int, 1024)
	buf := make([]byte, readChunk)
	var carry []byte // word that may continue past the end of a chunk

	for {
		n, err := r.Read(buf)
		chunk := buf[:n]
		for i := 0; i < len(chunk); {
			if len(carry) > 0 {
				for i < len(chunk) && isLetter(chunk[i]) {
					carry = append(carry, chunk[i]|0x20)
					i++
				}
				if i < len(chunk) {
					counts[string(carry)]++
					carry = carry[:0]
				}
				continue
			}

			for i < len(chunk) && !isLetter(chunk[i]) {
				i++
			}
			start := i
			for i < len(chunk) && isLetter(chunk[i]) {
				chunk[i] |= 0x20
				i++
			}
			switch {
			case i == start:
				// Only separators remained in this chunk.
			case i < len(chunk):
				counts[string(chunk[start:i])]++
			default:
				carry = append(carry, chunk[start:i]...)
			}
		}

		if err == io.EOF {
			break
		}
		if err != nil {
			flush(counts, carry)
			return counts, err
		}
	}
	flush(counts, carry)
	return counts, nil
}

func flush(counts map[string]int, carry []byte) {
	if len(carry) > 0 {
		counts[string(carry)]++
	}
}

// isLetter reports whether c is an ASCII letter.
func isLetter(c byte) bool {
	return (c|0x20)-'a' < 26
}
