// Command wordfreq reads standard input and prints the 10 most frequent
// ASCII-letter words, one "<count> <word>" line each.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"

	"wordfreq/internal/wordfreq"
)

const topN = 10

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}

	out := bufio.NewWriter(w)
	for _, e := range wordfreq.Top(wordfreq.Count(data), topN) {
		out.WriteString(strconv.Itoa(e.Count))
		out.WriteByte(' ')
		out.WriteString(e.Word)
		out.WriteByte('\n')
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}
