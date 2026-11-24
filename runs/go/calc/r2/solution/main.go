// Command calc evaluates one 64-bit signed integer expression per line of
// standard input and prints each result, or "error", on standard output.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "calc:", err)
	}
}

// run reads expressions line by line from r and writes results to w.
func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	buf := make([]byte, 0, 20)

	for {
		line, readErr := in.ReadBytes('\n')
		if readErr != nil && !errors.Is(readErr, io.EOF) {
			out.Flush()
			return readErr
		}
		line = bytes.TrimSuffix(line, []byte{'\n'})
		if !isBlank(line) {
			if v, err := Eval(line); err != nil {
				out.WriteString("error\n")
			} else {
				buf = strconv.AppendInt(buf[:0], v, 10)
				buf = append(buf, '\n')
				out.Write(buf)
			}
		}
		if readErr != nil {
			break
		}
	}
	return out.Flush()
}

func isBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}
