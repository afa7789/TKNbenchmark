// Command app evaluates 64-bit signed integer expressions, one per line of
// standard input, printing each value or "error". See SPEC.md.
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
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run reads every expression from r and writes one result line per
// non-blank input line to w.
func run(r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	data = bytes.TrimSuffix(data, []byte("\n"))

	out := bufio.NewWriterSize(w, 64*1024)
	var buf []byte
	for line := range bytes.SplitSeq(data, []byte("\n")) {
		if len(bytes.Trim(line, " \t")) == 0 {
			continue
		}
		buf = buf[:0]
		if v, err := Evaluate(string(line)); err != nil {
			buf = append(buf, "error"...)
		} else {
			buf = strconv.AppendInt(buf, v, 10)
		}
		buf = append(buf, '\n')
		if _, err := out.Write(buf); err != nil {
			return err
		}
	}
	return out.Flush()
}
