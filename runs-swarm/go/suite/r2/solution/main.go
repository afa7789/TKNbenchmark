// Command app is a suite of independent subcommands. The first argument
// selects the subcommand, which reads standard input and writes standard
// output as described in SPEC.md.
package main

import (
	"bufio"
	"fmt"
	"io"
	"maps"
	"os"
	"slices"
	"strings"

	"suite/internal/calc"
	"suite/internal/lru"
	"suite/internal/wordfreq"
)

// runFunc is the entry point shared by every subcommand. Implementations
// read all input from r and write all output to w; they need not buffer
// or flush w themselves.
type runFunc func(r io.Reader, w io.Writer) error

var subcommands = map[string]runFunc{
	"calc":     calc.Run,
	"lru":      lru.Run,
	"wordfreq": wordfreq.Run,
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	run, ok := subcommands[os.Args[1]]
	if !ok {
		fmt.Fprintf(os.Stderr, "app: unknown subcommand %q\n", os.Args[1])
		usage()
	}

	in := bufio.NewReaderSize(os.Stdin, 1<<16)
	out := bufio.NewWriterSize(os.Stdout, 1<<16)
	err := run(in, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "app %s: %v\n", os.Args[1], err)
		os.Exit(1)
	}
}

func usage() {
	names := slices.Sorted(maps.Keys(subcommands))
	fmt.Fprintf(os.Stderr, "usage: app <%s>\n", strings.Join(names, "|"))
	os.Exit(2)
}
