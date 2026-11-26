// Command app reads one integer expression per line from standard input and
// prints its value, or "error" if it has none. Blank lines print nothing.
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
		fmt.Fprintln(os.Stderr, "calc:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 64<<10)
	out := bufio.NewWriterSize(w, 64<<10)
	var (
		ev   calc.Evaluator
		long []byte // accumulates lines longer than the reader's buffer
		num  []byte
	)
	for {
		line, err := in.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			long = append(long, line...)
			continue
		}
		if len(long) > 0 {
			line = append(long, line...)
		}
		if len(line) > 0 && line[len(line)-1] == '\n' {
			line = line[:len(line)-1]
		}
		if len(line) > 0 && !calc.IsBlank(line) {
			if v, evalErr := ev.Evaluate(line); evalErr != nil {
				out.WriteString("error\n")
			} else {
				num = strconv.AppendInt(num[:0], v, 10)
				num = append(num, '\n')
				out.Write(num)
			}
		}
		long = long[:0]
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Flush()
			return fmt.Errorf("read error: %w", err)
		}
	}
	return out.Flush()
}
