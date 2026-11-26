// Command calc is a 64-bit signed integer expression evaluator (see SPEC.md).
//
// Each line of standard input is one expression; for each non-blank line the
// program prints its value or "error".
package main

import (
	"bufio"
	"bytes"
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

// run evaluates every line of r and writes the results to w.
func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return err
	}

	out := bufio.NewWriterSize(w, 64*1024)
	var ev evaluator
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
		buf = buf[:0]
		if v, ok := ev.evaluate(line); ok {
			buf = strconv.AppendInt(buf, v, 10)
		} else {
			buf = append(buf, "error"...)
		}
		buf = append(buf, '\n')
		if _, err := out.Write(buf); err != nil {
			return err
		}
	}
	return out.Flush()
}

func isBlank(c byte) bool { return c == ' ' || c == '\t' }

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func isBlankLine(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}
