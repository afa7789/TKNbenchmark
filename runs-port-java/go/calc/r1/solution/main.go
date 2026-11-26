// Command app evaluates one integer expression per line of standard input
// and prints its value, or "error".
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

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 1<<16)
	out := bufio.NewWriterSize(w, 1<<16)
	var buf []byte
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			buf = append(buf, line...)
			continue
		}
		if len(buf) > 0 {
			buf = append(buf, line...)
			line = buf
		}
		line = bytes.TrimSuffix(line, []byte{'\n'})
		emit(out, line)
		buf = buf[:0]
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Flush()
			return err
		}
	}
	return out.Flush()
}

func emit(out *bufio.Writer, line []byte) {
	if calc.IsBlank(line) {
		return
	}
	v, err := calc.Evaluate(line)
	if err != nil {
		out.WriteString("error\n")
		return
	}
	var num [20]byte
	out.Write(strconv.AppendInt(num[:0], v, 10))
	out.WriteByte('\n')
}
