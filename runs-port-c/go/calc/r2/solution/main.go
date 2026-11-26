// Command app reads one integer expression per line from standard input and
// prints its value, or "error" if it cannot be evaluated.
package main

import (
	"bufio"
	"bytes"
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
	input, err := io.ReadAll(r)
	if err != nil {
		return err
	}

	out := bufio.NewWriterSize(w, 1<<16)
	var ev calc.Evaluator
	var num []byte
	for len(input) > 0 {
		line, rest, _ := bytes.Cut(input, []byte{'\n'})
		input = rest
		if calc.IsBlank(line) {
			continue
		}
		if v, err := ev.Evaluate(line); err != nil {
			out.WriteString("error\n")
		} else {
			num = strconv.AppendInt(num[:0], v, 10)
			num = append(num, '\n')
			out.Write(num)
		}
	}
	return out.Flush()
}
