// Command app reads integer expressions from standard input, one per line,
// and prints each value or "error".
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
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var (
		buf []byte
		num [20]byte
	)
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Line longer than the buffer: accumulate it fully.
			buf = append(buf[:0], line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		line = bytes.TrimSuffix(line, []byte("\n"))
		if len(bytes.Trim(line, " \t")) > 0 {
			if v, evalErr := calc.Eval(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				out.Write(strconv.AppendInt(num[:0], v, 10))
				out.WriteByte('\n')
			}
		}
		if err != nil { // io.EOF
			return out.Flush()
		}
	}
}
