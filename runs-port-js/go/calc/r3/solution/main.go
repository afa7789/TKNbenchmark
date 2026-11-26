// Command calc evaluates 64-bit signed integer expressions read from
// standard input, one per line, printing each value or "error".
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "calc:", err)
		os.Exit(1)
	}
}

// run evaluates every line of r and writes the results to w.
func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var buf []byte
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Long line: accumulate it in buf until the newline arrives.
			buf = append(buf[:0], line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if err != nil && err != io.EOF {
			return err
		}
		if n := len(line); n > 0 && line[n-1] == '\n' {
			line = line[:n-1]
		}
		if !isBlank(line) {
			if v, evalErr := Evaluate(line); evalErr != nil {
				out.WriteString("error")
			} else {
				out.Write(strconv.AppendInt(out.AvailableBuffer(), v, 10))
			}
			out.WriteByte('\n')
		}
		if err == io.EOF {
			break
		}
	}
	return out.Flush()
}

// isBlank reports whether line holds only spaces and tabs.
func isBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}
