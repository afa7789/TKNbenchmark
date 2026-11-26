// Command app bundles three independent stdin/stdout tools: wordfreq, lru and calc.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
)

const usage = "usage: app <wordfreq|lru|calc> < input"

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}

	var run func(io.Reader, *bufio.Writer) error
	switch os.Args[1] {
	case "wordfreq":
		run = wordFreq
	case "lru":
		run = lru
	case "calc":
		run = calc
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand %q\n%s\n", os.Args[1], usage)
		os.Exit(2)
	}

	out := bufio.NewWriterSize(os.Stdout, 64*1024)
	err := run(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "app %s: %v\n", os.Args[1], err)
		os.Exit(1)
	}
}

// forEachLine calls fn with every line of r, without the trailing '\n'.
// The slice passed to fn is only valid until fn returns. A final line
// lacking '\n' is still delivered; lines may be arbitrarily long.
func forEachLine(r io.Reader, fn func(line []byte)) error {
	br := bufio.NewReaderSize(r, 64*1024)
	var long []byte // accumulates lines longer than the reader's buffer
	for {
		chunk, err := br.ReadSlice('\n')
		if err == bufio.ErrBufferFull {
			long = append(long, chunk...)
			continue
		}
		line := chunk
		if len(long) > 0 {
			long = append(long, chunk...)
			line = long
		}
		if n := len(line); n > 0 {
			if line[n-1] == '\n' {
				line = line[:n-1]
			}
			fn(line)
		}
		long = long[:0]
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}
