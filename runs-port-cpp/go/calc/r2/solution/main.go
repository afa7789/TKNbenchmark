// Command calc is a 64-bit signed integer expression evaluator.
//
// It reads one expression per line from standard input and prints its value
// or "error". Lines that are empty or contain only spaces and tabs produce no
// output.
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
		os.Exit(1)
	}
}

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
		if v, ok := ev.evaluate(line); ok {
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

func isBlankLine(line []byte) bool {
	for _, c := range line {
		if !isBlank(c) {
			return false
		}
	}
	return true
}
