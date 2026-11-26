// Command wordfreq prints the 10 most frequent ASCII words read from standard input.
package main

import (
	"bufio"
	"fmt"
	"os"
)

// topN is the maximum number of words printed.
const topN = 10

func main() {
	counts, err := countWords(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}

	w := bufio.NewWriter(os.Stdout)
	for _, e := range topWords(counts, topN) {
		fmt.Fprintf(w, "%d %s\n", e.count, e.word)
	}
	if err := w.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
