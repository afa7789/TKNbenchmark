// Command app simulates an LRU cache driven by commands read from standard
// input, as described in SPEC.md.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"lrusim/lru"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	out := bufio.NewWriterSize(w, 1<<16)

	lines := lineScanner{data: input}
	first, ok := lines.next()
	for ok && len(bytes.TrimSpace(first)) == 0 {
		first, ok = lines.next()
	}
	if !ok {
		return nil
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(first)))
	if err != nil {
		return fmt.Errorf("invalid capacity: %w", err)
	}
	if capacity < 1 {
		return errors.New("capacity must be positive")
	}

	cache := lru.New[string, string](capacity)
	for line, ok := lines.next(); ok; line, ok = lines.next() {
		execute(cache, line, out)
	}
	return out.Flush()
}

// execute applies one command line to the cache. Malformed, blank, or
// unrecognised lines produce no output.
func execute(cache *lru.Cache[string, string], line []byte, out *bufio.Writer) {
	cmd, rest, hasArg := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !hasArg || !ok {
			return
		}
		cache.Set(string(key), string(value))
	case "GET":
		if !hasArg {
			return
		}
		if v, ok := cache.Get(string(rest)); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if !hasArg {
			return
		}
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

// lineScanner splits a buffer into lines, tolerating a trailing '\r' and a
// missing final newline.
type lineScanner struct {
	data []byte
	pos  int
}

func (s *lineScanner) next() ([]byte, bool) {
	if s.pos >= len(s.data) {
		return nil, false
	}
	rest := s.data[s.pos:]
	line := rest
	if i := bytes.IndexByte(rest, '\n'); i >= 0 {
		line = rest[:i]
		s.pos += i + 1
	} else {
		s.pos = len(s.data)
	}
	line = bytes.TrimSuffix(line, []byte{'\r'})
	return line, true
}
