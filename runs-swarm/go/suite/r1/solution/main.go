// Command app is a suite of independent subcommands selected by the first
// argument. See SPEC.md for the behavior of each one.
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

// runFunc is the entry point of a subcommand. It reads its input from r and
// writes its output to w. Implementations need not buffer w; the caller
// buffers and flushes it.
type runFunc func(r io.Reader, w io.Writer) error

var commands = map[string]runFunc{
	"calc":     calc.Run,
	"lru":      lru.Run,
	"wordfreq": wordfreq.Run,
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) < 1 {
		fmt.Fprintf(stderr, "usage: app <%s>\n", strings.Join(names(), "|"))
		return 2
	}
	cmd, ok := commands[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "app: unknown subcommand %q (want one of: %s)\n", args[0], strings.Join(names(), ", "))
		return 2
	}

	out := bufio.NewWriterSize(stdout, 64<<10)
	err := cmd(stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintf(stderr, "app %s: %v\n", args[0], err)
		return 1
	}
	return 0
}

func names() []string {
	ns := make([]string, 0, len(commands))
	for n := range commands {
		ns = append(ns, n)
	}
	sort.Strings(ns)
	return ns
}
