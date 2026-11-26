// Command app evaluates one signed 64-bit integer expression per line of
// standard input, printing each result or "error".
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"calc/calc"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var buf []byte

	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Accumulate an over-long line before evaluating it.
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
			if v, evalErr := calc.Evaluate(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				out.Write(strconv.AppendInt(nil, v, 10))
				out.WriteByte('\n')
			}
		}
		if err != nil { // io.EOF
			break
		}
	}
	return out.Flush()
}
