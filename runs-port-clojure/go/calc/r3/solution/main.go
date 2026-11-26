// Command app reads one integer expression per line from standard input and
// prints its value, or "error" when it cannot be evaluated.
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
		fmt.Fprintln(os.Stderr, "app:", err)
	}
}

// run evaluates every newline-terminated line of in and writes results to out.
// A carriage return stays part of its line and is therefore a syntax error.
func run(in io.Reader, out io.Writer) error {
	r := bufio.NewReaderSize(in, 64*1024)
	w := bufio.NewWriterSize(out, 64*1024)
	var buf []byte
	for {
		line, err := r.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			// Long line: accumulate until the terminator arrives.
			buf = append(buf[:0], line...)
			for errors.Is(err, bufio.ErrBufferFull) {
				line, err = r.ReadSlice('\n')
				buf = append(buf, line...)
			}
			line = buf
		}
		if len(line) > 0 && line[len(line)-1] == '\n' {
			line = line[:len(line)-1]
		}
		if len(line) > 0 && !calc.IsBlank(line) {
			w.Write(evalLine(line))
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	return w.Flush()
}

var errorOut = []byte("error\n")

func evalLine(line []byte) []byte {
	v, err := calc.Eval(line)
	if err != nil {
		return errorOut
	}
	var b [24]byte
	return append(strconv.AppendInt(b[:0], v, 10), '\n')
}
