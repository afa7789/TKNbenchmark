// Command calc reads one integer expression per line from standard input
// and prints its value, or "error" if it cannot be evaluated.
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

	var (
		ev   calc.Evaluator
		line []byte
		num  []byte
	)
	for {
		var err error
		line, err = readLine(in, line[:0])
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		if !calc.IsBlank(line) {
			if v, evalErr := ev.Evaluate(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				num = strconv.AppendInt(num[:0], v, 10)
				num = append(num, '\n')
				out.Write(num)
			}
		}
		if err != nil { // io.EOF
			break
		}
	}
	return out.Flush()
}

// readLine appends the next line (without its '\n') to buf. It returns
// io.EOF when input ends; buf may still hold a final unterminated line.
func readLine(r *bufio.Reader, buf []byte) ([]byte, error) {
	for {
		chunk, err := r.ReadSlice('\n')
		buf = append(buf, chunk...)
		switch {
		case err == nil:
			return buf[:len(buf)-1], nil
		case errors.Is(err, bufio.ErrBufferFull):
			continue
		default:
			return buf, err
		}
	}
}
