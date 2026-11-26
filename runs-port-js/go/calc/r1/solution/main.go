// Command app reads one integer expression per line from standard input and
// prints its value, or "error". Blank lines produce no output.
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
	var num []byte
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Line longer than the buffer: accumulate the rest of it.
			buf := append([]byte(nil), line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if err != nil && err != io.EOF {
			return err
		}
		if n := len(line); n > 0 && line[n-1] == '\n' {
			line = line[:n-1]
		}
		if !calc.IsBlank(line) {
			if v, evalErr := calc.Eval(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				num = strconv.AppendInt(num[:0], v, 10)
				num = append(num, '\n')
				out.Write(num)
			}
		}
		if err == io.EOF {
			break
		}
	}
	return out.Flush()
}
