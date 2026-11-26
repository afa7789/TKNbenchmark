// Command app evaluates one signed 64-bit integer expression per line of
// standard input, printing its value or "error". Blank lines print nothing.
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
		fmt.Fprintln(os.Stderr, "calc:", err)
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
			// Long line: accumulate until the terminator arrives.
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
		if len(line) > 0 {
			if line[len(line)-1] == '\n' {
				line = line[:len(line)-1]
			}
			if !isBlank(line) {
				out.Write(evaluate(line))
				out.WriteByte('\n')
			}
		}
		if err != nil { // io.EOF
			return out.Flush()
		}
	}
}

var errorText = []byte("error")

func evaluate(line []byte) []byte {
	v, err := calc.Eval(line)
	if err != nil {
		return errorText
	}
	return strconv.AppendInt(nil, v, 10)
}

func isBlank(line []byte) bool {
	for _, c := range line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}
