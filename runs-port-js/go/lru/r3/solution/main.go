// Command app simulates an LRU cache driven by commands on standard input.
//
// The first input line holds the capacity; each later line is one of
// SET <key> <value>, GET <key>, DEL <key> or SIZE.
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
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	first, rest, _ := bytes.Cut(input, []byte{'\n'})
	capacity, err := parseCapacity(first)
	if err != nil {
		return err
	}

	cache := lru.New(capacity)
	out := bufio.NewWriterSize(w, 1<<16)
	for len(rest) > 0 {
		var line []byte
		line, rest, _ = bytes.Cut(rest, []byte{'\n'})
		line = bytes.TrimSuffix(line, []byte{'\r'})
		if len(line) == 0 {
			continue
		}
		execute(cache, out, line)
	}
	return out.Flush()
}

// execute applies one command line to the cache, writing any output to out.
// Unknown or malformed commands are ignored.
func execute(cache *lru.Cache, out *bufio.Writer, line []byte) {
	cmd, args, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(args, []byte{' '})
		if ok {
			cache.Set(string(key), string(value))
		}
	case "GET":
		if value, ok := cache.Get(string(args)); ok {
			out.WriteString(value)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if cache.Delete(string(args)) {
			out.WriteString("1\n")
		} else {
			out.WriteString("0\n")
		}
	case "SIZE":
		out.WriteString(strconv.Itoa(cache.Len()))
		out.WriteByte('\n')
	}
}

// parseCapacity reads the leading integer of the first line, tolerating
// surrounding whitespace and trailing garbage.
func parseCapacity(line []byte) (int, error) {
	line = bytes.TrimLeft(line, " \t\r")
	end := 0
	for end < len(line) && line[end] >= '0' && line[end] <= '9' {
		end++
	}
	n, err := strconv.Atoi(string(line[:end]))
	if err != nil || n < 1 {
		return 0, fmt.Errorf("invalid capacity %q", line)
	}
	return n, nil
}
