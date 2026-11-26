// Command app simulates an LRU cache: it reads a capacity followed by a
// stream of SET/GET/DEL/SIZE commands from standard input and writes the
// results to standard output.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
)

const bufSize = 1 << 16

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run processes the whole input from r, writing command output to w.
func run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, bufSize), 1<<20)
	out := bufio.NewWriterSize(w, bufSize)

	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return err
		}
		return out.Flush()
	}
	capacity, err := strconv.Atoi(string(trim(sc.Bytes())))
	if err != nil {
		return fmt.Errorf("invalid capacity: %w", err)
	}

	cache := NewCache(capacity)
	for sc.Scan() {
		if line := trim(sc.Bytes()); len(line) > 0 {
			execute(cache, out, line)
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return out.Flush()
}

// execute runs one command line against the cache. Unknown or malformed
// commands are ignored.
func execute(cache *Cache, out *bufio.Writer, line []byte) {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if ok {
			cache.Set(string(key), string(value))
		}
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

// trim strips leading and trailing ASCII whitespace and control characters,
// matching the line handling of the original implementation.
func trim(b []byte) []byte {
	return bytes.TrimFunc(b, func(r rune) bool { return r <= ' ' })
}
