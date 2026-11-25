// Command app simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each later line is one of
// SET <key> <value>, GET <key>, DEL <key> or SIZE.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"lru/internal/lru"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	in := bufio.NewReaderSize(r, 1<<16)
	out := bufio.NewWriterSize(w, 1<<16)

	first, err := readLine(in)
	if err != nil {
		if errors.Is(err, io.EOF) {
			return nil
		}
		return fmt.Errorf("read capacity: %w", err)
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(first)))
	if err != nil || capacity < 1 {
		return fmt.Errorf("invalid capacity %q", first)
	}
	cache := lru.New(capacity)

	for {
		line, err := readLine(in)
		if err != nil {
			if errors.Is(err, io.EOF) {
				break
			}
			return fmt.Errorf("read command: %w", err)
		}
		execute(cache, line, out)
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("write output: %w", err)
	}
	return nil
}

// execute applies one command line to the cache, writing any result to out.
// Malformed lines are ignored.
func execute(cache *lru.Cache, line []byte, out *bufio.Writer) {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !ok || len(key) == 0 || len(value) == 0 {
			return
		}
		cache.Set(string(key), string(value))
	case "GET":
		if len(rest) == 0 {
			return
		}
		if v, ok := cache.Get(string(rest)); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if len(rest) == 0 {
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

// readLine returns the next line without its terminator (\n or \r\n).
// The returned slice is only valid until the next call. It returns io.EOF
// once the input is exhausted; a final line lacking \n is still returned.
func readLine(in *bufio.Reader) ([]byte, error) {
	line, err := in.ReadSlice('\n')
	if errors.Is(err, bufio.ErrBufferFull) {
		// Overlong line: accumulate it in full.
		buf := append([]byte(nil), line...)
		for errors.Is(err, bufio.ErrBufferFull) {
			line, err = in.ReadSlice('\n')
			buf = append(buf, line...)
		}
		line = buf
	}
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	if len(line) == 0 && err != nil {
		return nil, io.EOF
	}
	line = bytes.TrimSuffix(line, []byte{'\n'})
	line = bytes.TrimSuffix(line, []byte{'\r'})
	return line, nil
}
