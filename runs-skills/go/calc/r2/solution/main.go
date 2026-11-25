// Command app evaluates one 64-bit signed integer expression per line of
// standard input and prints each result, or "error".
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"calc/internal/calc"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var num []byte
	for {
		line, readErr := in.ReadBytes('\n')
		if readErr != nil && !errors.Is(readErr, io.EOF) {
			out.Flush()
			return fmt.Errorf("read stdin: %w", readErr)
		}
		line = bytes.TrimSuffix(line, []byte{'\n'})
		if len(bytes.Trim(line, " \t")) > 0 {
			if v, err := calc.Eval(line); err != nil {
				out.WriteString("error\n")
			} else {
				num = strconv.AppendInt(num[:0], v, 10)
				num = append(num, '\n')
				out.Write(num)
			}
		}
		if readErr != nil {
			break
		}
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("write stdout: %w", err)
	}
	return nil
}
