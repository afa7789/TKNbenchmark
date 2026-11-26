// Command app reads standard input and prints the 10 most frequent ASCII words.
package main

import (
	"bufio"
	"fmt"
	"os"

	"wordfreq/wordfreq"
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
		return err
	}

	w := bufio.NewWriter(os.Stdout)
	for _, e := range counter.Top(topN) {
		fmt.Fprintf(w, "%d %s\n", e.Count, e.Word)
	}
	return w.Flush()
}
