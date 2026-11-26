// Command app evaluates one 64-bit signed integer expression per line of
// standard input, printing each value or "error". See SPEC.md.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
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
	var line, buf []byte

	for {
		var err error
		line, err = readLine(in, line[:0])
		if len(line) > 0 && !isBlankLine(line) {
			if v, evalErr := Evaluate(line); evalErr != nil {
				buf = append(buf[:0], "error\n"...)
			} else {
				buf = strconv.AppendInt(buf[:0], v, 10)
				buf = append(buf, '\n')
			}
			if _, werr := out.Write(buf); werr != nil {
				return werr
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	return out.Flush()
}

// readLine appends the next line (without its '\n') to dst. It returns io.EOF
// together with the final, unterminated line, if any.
func readLine(r *bufio.Reader, dst []byte) ([]byte, error) {
	for {
		chunk, err := r.ReadSlice('\n')
		dst = append(dst, chunk...)
		switch {
		case err == nil:
			return dst[:len(dst)-1], nil
		case errors.Is(err, bufio.ErrBufferFull):
			continue
		default:
			return dst, err
		}
	}
}

func isBlankLine(line []byte) bool {
	return len(bytes.Trim(line, " \t")) == 0
}
