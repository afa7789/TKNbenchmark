// Command app bundles three independent stdin/stdout tools: wordfreq, lru and calc.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

const usage = "usage: app <wordfreq|lru|calc>"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}

	var run func(io.Reader, *bufio.Writer) error
	switch os.Args[1] {
	case "wordfreq":
		run = wordFreq
	case "lru":
		run = lruSim
	case "calc":
		run = calc
	default:
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}

	out := bufio.NewWriterSize(os.Stdout, 64*1024)
	err := run(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}
