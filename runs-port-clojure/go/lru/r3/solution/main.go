// Command app simulates an LRU cache. It reads a capacity followed by one
// command per line from standard input and writes results to standard output.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"

	"lru/internal/lru"
)

func main() {
	out := bufio.NewWriterSize(os.Stdout, 1<<16)
	err := run(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

// run processes the whole command stream from in, writing results to out.
func run(in io.Reader, out *bufio.Writer) error {
	lines := bufio.NewScanner(in)
	lines.Buffer(make([]byte, 0, 1<<16), 1<<30)
	lines.Split(scanLines)
	if !lines.Scan() {
		return lines.Err()
	}
	capacity, err := strconv.Atoi(string(trim(lines.Bytes())))
	if err != nil {
		return fmt.Errorf("invalid capacity: %w", err)
	}
	cache := lru.New[string, string](capacity)
	for lines.Scan() {
		if line := trim(lines.Bytes()); len(line) > 0 {
			execute(cache, out, line)
		}
	}
	return lines.Err()
}

// execute runs a single non-empty command line. Unknown commands are ignored.
func execute(cache *lru.Cache[string, string], out *bufio.Writer, line []byte) {
	op, rest, hasArgs := bytes.Cut(line, []byte{' '})
	if !hasArgs {
		// A bare command takes the whole line as its argument.
		rest = line
	}
	switch string(op) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !ok {
			return
		}
		cache.Set(string(key), string(value))
	case "GET":
		if v, ok := cache.Get(string(rest)); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if cache.Delete(string(rest)) {
			out.WriteString("1\n")
		} else {
			out.WriteString("0\n")
		}
	case "SIZE":
		out.Write(strconv.AppendInt(out.AvailableBuffer(), int64(cache.Len()), 10))
		out.WriteByte('\n')
	}
}

// trim removes leading and trailing ASCII control characters and spaces.
func trim(b []byte) []byte {
	start, end := 0, len(b)
	for start < end && b[start] <= ' ' {
		start++
	}
	for end > start && b[end-1] <= ' ' {
		end--
	}
	return b[start:end]
}

// scanLines is a bufio.SplitFunc that splits on "\n", "\r" or "\r\n",
// matching the line terminators accepted by the original implementation.
func scanLines(data []byte, atEOF bool) (advance int, token []byte, err error) {
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
		return 0, nil, nil // need one more byte to tell "\r" from "\r\n"
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}
