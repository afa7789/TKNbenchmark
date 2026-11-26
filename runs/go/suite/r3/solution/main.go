// Command app bundles three independent stdin/stdout tools: wordfreq, lru and calc.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"

	"suite/calc"
	"suite/lru"
	"suite/wordfreq"
)

type command func(r io.Reader, w io.Writer) error

var commands = map[string]command{
	"wordfreq": func(r io.Reader, w io.Writer) error { return wordfreq.Run(r, w, 10) },
	"lru":      lru.Run,
	"calc":     calc.Run,
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	cmd, ok := commands[os.Args[1]]
	if !ok {
		usage()
	}
	out := bufio.NewWriterSize(os.Stdout, 1<<16)
	err := cmd(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "app %s: %v\n", os.Args[1], err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: app wordfreq|lru|calc < input")
	os.Exit(2)
}
