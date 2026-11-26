// Command app reads one integer expression per line from standard input and
// prints its value, or "error" if it cannot be evaluated.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"strconv"

	"calc/internal/calc"
)

const maxLine = 1 << 30

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
	}
}

func run(in *os.File, out *os.File) error {
	sc := bufio.NewScanner(bufio.NewReaderSize(in, 64*1024))
	sc.Buffer(make([]byte, 64*1024), maxLine)
	sc.Split(scanLines)
	w := bufio.NewWriterSize(out, 64*1024)
	defer w.Flush()

	buf := make([]byte, 0, 32)
	for sc.Scan() {
		line := sc.Bytes()
		if calc.IsBlank(line) {
			continue
		}
		buf = buf[:0]
		if v, err := calc.Eval(line); err != nil {
			buf = append(buf, "error"...)
		} else {
			buf = strconv.AppendInt(buf, v, 10)
		}
		buf = append(buf, '\n')
		if _, err := w.Write(buf); err != nil {
			return err
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return w.Flush()
}

// scanLines splits input into lines terminated by "\n", "\r" or "\r\n",
// matching the line handling of the original implementation.
func scanLines(data []byte, atEOF bool) (advance int, token []byte, err error) {
	if atEOF && len(data) == 0 {
		return 0, nil, nil
	}
	if i := bytes.IndexAny(data, "\r\n"); i >= 0 {
		if data[i] == '\n' {
			return i + 1, data[:i], nil
		}
		if i+1 < len(data) {
			if data[i+1] == '\n' {
				return i + 2, data[:i], nil
			}
			return i + 1, data[:i], nil
		}
		if atEOF {
			return i + 1, data[:i], nil
		}
		return 0, nil, nil // need more data to see whether "\n" follows
	}
	if atEOF {
		return len(data), data, nil
	}
	return 0, nil, nil
}
