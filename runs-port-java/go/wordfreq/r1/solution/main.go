// Command wordfreq reads standard input and prints the ten most frequent
// ASCII words, one "<count> <word>" line each.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
)

const topN = 10

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "wordfreq:", err)
		os.Exit(1)
	}
}

func run() error {
	counts, err := Count(os.Stdin)
	if err != nil {
		return err
	}
	out := bufio.NewWriter(os.Stdout)
	var line []byte
	for _, e := range Top(counts, topN) {
		line = strconv.AppendInt(line[:0], int64(e.Count), 10)
		line = append(line, ' ')
		line = append(line, e.Word...)
		line = append(line, '\n')
		if _, err := out.Write(line); err != nil {
			return err
		}
	}
	return out.Flush()
}
