// Command app simulates an LRU cache driven by commands read from standard
// input. See SPEC.md for the input format.
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
	input, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}

	header, rest, _ := bytes.Cut(input, []byte{'\n'})
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(header)))
	if err != nil {
		return fmt.Errorf("invalid capacity: %w", err)
	}
	if capacity < 1 {
		return errors.New("invalid capacity: must be at least 1")
	}

	out := bufio.NewWriterSize(w, 1<<16)
	// Values are kept as subslices of input, which stays alive for the whole
	// run anyway; this avoids an allocation per SET.
	cache := lru.New[[]byte](capacity)

	for len(rest) > 0 {
		var line []byte
		line, rest, _ = bytes.Cut(rest, []byte{'\n'})
		line = bytes.TrimSuffix(line, []byte{'\r'})
		execute(cache, line, out)
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}

// execute applies one command line to cache, writing any result to out.
// Blank and unrecognised lines are ignored.
func execute(cache *lru.Cache[[]byte], line []byte, out *bufio.Writer) {
	cmd, args, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		if key, value, ok := bytes.Cut(args, []byte{' '}); ok {
			cache.Set(string(key), value)
		}
	case "GET":
		if value, ok := cache.Get(string(args)); ok {
			out.Write(value)
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
