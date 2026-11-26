// Command app is a 64-bit signed integer expression evaluator.
//
// Each line of standard input is one expression; for each non-blank line it
// prints the value or "error".
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
)

func isBlankLine(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	out := bufio.NewWriterSize(w, 64*1024)
	var e evaluator
	var buf []byte
	for len(input) > 0 {
		line := input
		if i := bytes.IndexByte(input, '\n'); i >= 0 {
			line, input = input[:i], input[i+1:]
		} else {
			input = nil
		}
		if isBlankLine(line) {
			continue
		}
		if v, err := e.eval(line); err == nil {
			buf = strconv.AppendInt(buf[:0], v, 10)
		} else {
			buf = append(buf[:0], "error"...)
		}
		buf = append(buf, '\n')
		if _, err := out.Write(buf); err != nil {
			return err
		}
	}
	return out.Flush()
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
