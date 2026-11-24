// Command calc evaluates one 64-bit signed integer expression per input line.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "calc:", err)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64*1024)
	out := bufio.NewWriterSize(w, 64*1024)
	var buf, num []byte
	for {
		line, err := in.ReadSlice('\n')
		if err == bufio.ErrBufferFull {
			// Long line: accumulate until the delimiter is found.
			buf = append(buf[:0], line...)
			for err == bufio.ErrBufferFull {
				line, err = in.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if err != nil && err != io.EOF {
			return err
		}
		line = bytes.TrimSuffix(line, []byte{'\n'})
		if len(bytes.Trim(line, " \t")) > 0 {
			if v, evalErr := Eval(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				num = strconv.AppendInt(num[:0], v, 10)
				out.Write(num)
				out.WriteByte('\n')
			}
		}
		if err == io.EOF {
			break
		}
	}
	return out.Flush()
}
