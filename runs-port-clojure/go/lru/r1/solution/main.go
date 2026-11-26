// Command app simulates an LRU cache. It reads a capacity followed by
// SET/GET/DEL/SIZE commands from standard input and writes results to
// standard output.
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
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

// run processes the full command stream from r, writing results to w.
func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 1<<20)
	out := bufio.NewWriterSize(w, 1<<20)

	first, err := readLine(in)
	if first == nil && err != nil {
		if err == io.EOF {
			return nil
		}
		return err
	}
	capacity, perr := strconv.Atoi(string(bytes.TrimSpace(first)))
	if perr != nil {
		return fmt.Errorf("invalid capacity: %w", perr)
	}
	cache := NewCache(capacity)

	for err == nil {
		var line []byte
		line, err = readLine(in)
		if len(line) > 0 {
			execute(cache, out, line)
		}
	}
	if err != io.EOF {
		return err
	}
	return out.Flush()
}

// readLine returns the next line without its trailing "\n" or "\r\n".
// The returned slice is only valid until the next read.
func readLine(r *bufio.Reader) ([]byte, error) {
	line, err := r.ReadSlice('\n')
	if err == bufio.ErrBufferFull {
		// Rare: a line longer than the buffer. Accumulate it.
		buf := append([]byte(nil), line...)
		for err == bufio.ErrBufferFull {
			line, err = r.ReadSlice('\n')
			buf = append(buf, line...)
		}
		line = buf
	}
	if err == io.EOF && len(line) == 0 {
		return nil, io.EOF
	}
	line = bytes.TrimSuffix(line, []byte("\n"))
	line = bytes.TrimSuffix(line, []byte("\r"))
	return line, err
}

// execute runs a single command line against cache. Unknown commands are
// ignored.
func execute(cache *Cache, out *bufio.Writer, line []byte) {
	cmd, rest, _ := bytes.Cut(line, []byte(" "))
	switch string(cmd) {
	case "SET":
		key, value, _ := bytes.Cut(rest, []byte(" "))
		cache.Set(string(key), string(value))
	case "GET":
		// string(rest) in a map lookup does not allocate.
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
