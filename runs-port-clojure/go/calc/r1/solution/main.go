// Command calc evaluates one 64-bit signed integer expression per line of
// standard input, printing each value or "error". Blank lines print nothing.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"strconv"
)

func main() {
	// Deeply nested expressions recurse deeply; allow a generous stack.
	debug.SetMaxStack(4 << 30)

	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "calc:", err)
		os.Exit(1)
	}
}

// run evaluates every line of r and writes the results to w. Lines are split
// on '\n' only, so a stray '\r' is reported as a syntax error.
func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)

	var (
		line    []byte
		buf     []byte
		scratch [20]byte // fits any int64 in decimal
	)
	for {
		chunk, err := in.ReadSlice('\n')
		switch {
		case errors.Is(err, bufio.ErrBufferFull):
			// Line longer than the reader buffer: accumulate and continue.
			buf = append(buf, chunk...)
			continue
		case err != nil && !errors.Is(err, io.EOF):
			return err
		}

		if len(buf) > 0 {
			buf = append(buf, chunk...)
			line = buf
		} else {
			line = chunk
		}
		if n := len(line); n > 0 && line[n-1] == '\n' {
			line = line[:n-1]
		}

		if !IsBlankLine(line) {
			if v, evalErr := Evaluate(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				out.Write(strconv.AppendInt(scratch[:0], v, 10))
				out.WriteByte('\n')
			}
		}
		buf = buf[:0]

		if err != nil { // io.EOF
			break
		}
	}
	return out.Flush()
}
