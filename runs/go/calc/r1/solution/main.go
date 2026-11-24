// Command app reads one integer expression per line from standard input and
// prints its value, or "error" if it cannot be evaluated.
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
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var buf []byte
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Long line: accumulate until the newline arrives.
			buf = append(buf[:0], line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if err != nil && err != io.EOF {
			return err
		}
		process(out, bytes.TrimSuffix(line, []byte{'\n'}))
		if err == io.EOF {
			break
		}
	}
	return out.Flush()
}

func process(out *bufio.Writer, line []byte) {
	if len(bytes.Trim(line, " \t")) == 0 {
		return
	}
	v, err := calc.Eval(line)
	if err != nil {
		out.WriteString("error\n")
		return
	}
	out.Write(strconv.AppendInt(out.AvailableBuffer(), v, 10))
	out.WriteByte('\n')
}
