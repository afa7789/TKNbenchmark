// Command app reads standard input and prints the 10 most frequent words.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"

	"wordfreq/internal/wordfreq"
)

const topN = 10

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "wordfreq: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	counter := wordfreq.NewCounter()
	if _, err := counter.ReadFrom(os.Stdin); err != nil {
		return fmt.Errorf("read error: %w", err)
	}

	out := bufio.NewWriter(os.Stdout)
	var line []byte
	for _, wc := range counter.Top(topN) {
		line = strconv.AppendInt(line[:0], int64(wc.Count), 10)
		line = append(line, ' ')
		line = append(line, wc.Word...)
		line = append(line, '\n')
		if _, err := out.Write(line); err != nil {
			return fmt.Errorf("write error: %w", err)
		}
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("write error: %w", err)
	}
	return nil
}
