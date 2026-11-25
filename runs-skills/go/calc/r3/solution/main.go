// Command app reads one integer expression per line from standard input
// and prints each value, or "error" if the expression cannot be evaluated.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"calc/internal/calc"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

func run(in io.Reader, out io.Writer) error {
	r := bufio.NewReaderSize(in, 64*1024)
	w := bufio.NewWriterSize(out, 64*1024)
	var buf []byte
	for {
		line, err := r.ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			return fmt.Errorf("read input: %w", err)
		}
		expr := strings.TrimSuffix(line, "\n")
		if strings.Trim(expr, " \t") != "" {
			if v, evalErr := calc.Eval(expr); evalErr != nil {
				buf = append(buf[:0], "error\n"...)
			} else {
				buf = strconv.AppendInt(buf[:0], v, 10)
				buf = append(buf, '\n')
			}
			if _, werr := w.Write(buf); werr != nil {
				return fmt.Errorf("write output: %w", werr)
			}
		}
		if err != nil {
			break
		}
	}
	if err := w.Flush(); err != nil {
		return fmt.Errorf("write output: %w", err)
	}
	return nil
}
