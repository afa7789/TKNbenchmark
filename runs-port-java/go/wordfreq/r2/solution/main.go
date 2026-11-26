// Command wordfreq prints the ten most frequent ASCII-letter words read from
// standard input, one "<count> <word>" line each.
package main

import (
	"bufio"
	"fmt"
	"os"
)

const topN = 10

func main() {
	counts, err := CountWords(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}

	w := bufio.NewWriter(os.Stdout)
	for _, e := range Top(counts, topN) {
		fmt.Fprintf(w, "%d %s\n", e.Count, e.Word)
	}
	if err := w.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
