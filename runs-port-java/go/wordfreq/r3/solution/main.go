// Command wordfreq prints the ten most frequent ASCII words read from standard input.
package main

import (
	"bufio"
	"fmt"
	"os"
)

const topN = 10

func main() {
	counter, err := Count(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}

	out := bufio.NewWriter(os.Stdout)
	for _, wc := range counter.Top(topN) {
		fmt.Fprintf(out, "%d %s\n", wc.Count, wc.Word)
	}
	if err := out.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}
