// Command wordfreq prints the 10 most frequent ASCII words read from standard input.
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

	out := bufio.NewWriter(os.Stdout)
	for _, wc := range TopWords(counts, topN) {
		fmt.Fprintf(out, "%d %s\n", wc.Count, wc.Word)
	}
	if err := out.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
