// Command app prints the 10 most frequent ASCII words read from standard input.
package main

import (
	"fmt"
	"os"
)

const topN = 10

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}

func run() error {
	c := NewCounter()
	if _, err := c.ReadFrom(os.Stdin); err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	return WriteEntries(os.Stdout, c.Top(topN))
}
