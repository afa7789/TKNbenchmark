// Command calc is a 64-bit signed integer expression evaluator.
//
// It reads one expression per line from standard input and prints its value
// or "error". Blank lines (empty or only spaces/tabs) produce no output.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"

	"calc/calc"
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
	var ev calc.Evaluator
	var num []byte

	for len(input) > 0 {
		line, rest, _ := bytes.Cut(input, []byte{'\n'})
		input = rest

		if isBlank(line) {
			continue
		}
		if v, ok := ev.Evaluate(line); ok {
			num = strconv.AppendInt(num[:0], v, 10)
			out.Write(num)
		} else {
			out.WriteString("error")
		}
		out.WriteByte('\n')
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
