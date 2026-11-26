// Command app evaluates one 64-bit signed integer expression per line of
// standard input and prints its value, or "error" if it cannot be evaluated.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"calc/internal/calc"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run evaluates every line read from r and writes one result per non-blank
// line to w.
func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var ev calc.Evaluator
	var buf, num []byte

	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Accumulate an overlong line into a private buffer.
			buf = append(buf[:0], line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if n := len(line); n > 0 && line[n-1] == '\n' {
			line = line[:n-1]
		}
		if !calc.IsBlank(line) {
			if v, evalErr := ev.Eval(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				num = strconv.AppendInt(num[:0], v, 10)
				num = append(num, '\n')
				out.Write(num)
			}
		}
		if err != nil { // io.EOF
			break
		}
	}
	return out.Flush()
}
