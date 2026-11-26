// Command app evaluates one signed 64-bit integer expression per line of
// standard input and prints each value, or "error".
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
	buf := make([]byte, 0, 64)

	for {
		line, err := in.ReadBytes('\n')
		if len(line) > 0 && line[len(line)-1] == '\n' {
			line = line[:len(line)-1]
		}
		if len(line) > 0 || err == nil {
			if v, evalErr := calc.Evaluate(line); errors.Is(evalErr, calc.ErrBlank) {
				// Blank lines produce no output.
			} else if evalErr != nil {
				out.WriteString("error\n")
			} else {
				buf = strconv.AppendInt(buf[:0], v, 10)
				buf = append(buf, '\n')
				out.Write(buf)
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	return out.Flush()
}
