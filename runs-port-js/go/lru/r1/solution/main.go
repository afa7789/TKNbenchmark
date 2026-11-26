// Command app simulates an LRU cache driven by commands read from stdin.
// See SPEC.md for the input format.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"

	"lru-sim/lru"
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
		return fmt.Errorf("reading input: %w", err)
	}

	first, rest, _ := bytes.Cut(input, []byte{'\n'})
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(first)))
	if err != nil || capacity < 1 {
		return fmt.Errorf("invalid capacity %q", first)
	}
	cache := lru.New(capacity)

	out := bufio.NewWriterSize(w, 64<<10)
	for len(rest) > 0 {
		var line []byte
		line, rest, _ = bytes.Cut(rest, []byte{'\n'})
		line = bytes.TrimSuffix(line, []byte{'\r'})
		if len(line) == 0 {
			continue
		}
		execute(cache, line, out)
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}

// execute applies one command line to cache, writing any result to out.
// Unknown commands are ignored.
func execute(cache *lru.Cache, line []byte, out *bufio.Writer) {
	cmd, args, _ := bytes.Cut(line, []byte{' '})
	key, args, _ := bytes.Cut(args, []byte{' '})
	switch string(cmd) {
	case "SET":
		value, _, _ := bytes.Cut(args, []byte{' '})
		cache.Set(string(key), string(value))
	case "GET":
		if v, ok := cache.Get(string(key)); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if cache.Delete(string(key)) {
			out.WriteString("1\n")
		} else {
			out.WriteString("0\n")
		}
	case "SIZE":
		out.WriteString(strconv.Itoa(cache.Len()))
		out.WriteByte('\n')
	}
}
