// Command calc is a 64-bit signed integer expression evaluator.
//
// It reads one expression per line from standard input and prints its value,
// or "error" for syntax errors, division by zero, and 64-bit overflow.
// Blank lines (empty or only spaces/tabs) produce no output.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"calc/calc"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "calc:", err)
	}
}

// run evaluates every line of r and writes one result line per non-blank line to w.
func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	defer out.Flush()

	var buf []byte
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Long line: accumulate until the newline (or EOF).
			buf = append(buf[:0], line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if len(line) > 0 {
			if werr := processLine(out, bytes.TrimSuffix(line, []byte{'\n'})); werr != nil {
				return werr
			}
		}
		if err == io.EOF {
			return out.Flush()
		}
		if err != nil {
			return err
		}
	}
}

func processLine(out *bufio.Writer, line []byte) error {
	if len(bytes.Trim(line, " \t")) == 0 {
		return nil
	}
	var scratch [24]byte
	res := []byte("error")
	if v, err := calc.Evaluate(line); err == nil {
		res = strconv.AppendInt(scratch[:0], v, 10)
	}
	res = append(res, '\n')
	_, err := out.Write(res)
	return err
}
