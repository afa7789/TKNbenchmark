// Command wordfreq reads all of standard input and prints the 10 most
// frequent ASCII words, one "<count> <word>" line each.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

const topN = 10

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "wordfreq: %v\n", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	out := bufio.NewWriter(w)
	for _, wc := range topWords(countWords(input), topN) {
		fmt.Fprintf(out, "%d %s\n", wc.Count, wc.Word)
	}
	return out.Flush()
}
