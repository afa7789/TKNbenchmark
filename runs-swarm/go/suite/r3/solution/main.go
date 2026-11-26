// Command app is a suite of independent stdin-to-stdout tools.
//
// Usage:
//
//	app <subcommand>
//
// The subcommands are wordfreq, lru and calc; see SPEC.md.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"suite/internal/calc"
	"suite/internal/lru"
	"suite/internal/wordfreq"
)

// runFunc is the entry point shared by every subcommand. It reads its input
// from r and writes its output to w. w is buffered; the caller flushes it
// after runFunc returns.
type runFunc func(r io.Reader, w io.Writer) error

var subcommands = map[string]runFunc{
	"wordfreq": wordfreq.Run,
	"lru":      lru.Run,
	"calc":     calc.Run,
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) < 1 {
		usage()
		return 2
	}
	cmd, ok := subcommands[args[0]]
	if !ok {
		fmt.Fprintf(os.Stderr, "app: unknown subcommand %q\n", args[0])
		usage()
		return 2
	}

	out := bufio.NewWriterSize(os.Stdout, 64<<10)
	err := cmd(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "app %s: %v\n", args[0], err)
		return 1
	}
	return 0
}

func usage() {
	names := make([]string, 0, len(subcommands))
	for name := range subcommands {
		names = append(names, name)
	}
	sort.Strings(names)
	fmt.Fprintf(os.Stderr, "usage: app <%s>\n", strings.Join(names, "|"))
}
