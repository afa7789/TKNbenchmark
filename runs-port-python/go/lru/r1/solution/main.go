// Command app simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each later line is one of
// "SET <key> <value>", "GET <key>", "DEL <key>" or "SIZE".
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run reads the whole input, executes every command, and writes the results.
// Keys and values are substrings of the input, so they are never copied.
func run(r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	input := string(data)

	first, rest, _ := strings.Cut(input, "\n")
	first = strings.TrimSpace(first)
	if first == "" {
		return nil
	}
	capacity, err := strconv.Atoi(first)
	if err != nil {
		return fmt.Errorf("invalid capacity %q: %w", first, err)
	}
	if capacity < 1 {
		return fmt.Errorf("capacity must be at least 1, got %d", capacity)
	}

	out := bufio.NewWriterSize(w, 1<<16)
	cache := NewCache(capacity)
	var fields [3]string
	for len(rest) > 0 {
		var line string
		line, rest, _ = strings.Cut(rest, "\n")
		n := splitFields(line, fields[:])
		if n == 0 {
			continue
		}
		execute(cache, out, fields[:n])
	}
	return out.Flush()
}

// execute applies one command, writing its output line if it produces one.
// Unknown or malformed commands are ignored.
func execute(cache *Cache, out *bufio.Writer, args []string) {
	switch args[0] {
	case "SET":
		if len(args) >= 3 {
			cache.Set(args[1], args[2])
		}
	case "GET":
		if len(args) >= 2 {
			if v, ok := cache.Get(args[1]); ok {
				out.WriteString(v)
			} else {
				out.WriteString("NULL")
			}
			out.WriteByte('\n')
		}
	case "DEL":
		if len(args) >= 2 {
			if cache.Delete(args[1]) {
				out.WriteString("1\n")
			} else {
				out.WriteString("0\n")
			}
		}
	case "SIZE":
		var buf [20]byte
		out.Write(strconv.AppendInt(buf[:0], int64(cache.Len()), 10))
		out.WriteByte('\n')
	}
}

// splitFields stores up to len(dst) whitespace-separated fields of s in dst
// and returns how many were stored.
func splitFields(s string, dst []string) int {
	n := 0
	i := 0
	for n < len(dst) {
		for i < len(s) && isSpace(s[i]) {
			i++
		}
		if i == len(s) {
			break
		}
		start := i
		for i < len(s) && !isSpace(s[i]) {
			i++
		}
		dst[n] = s[start:i]
		n++
	}
	return n
}

func isSpace(b byte) bool {
	switch b {
	case ' ', '\t', '\n', '\v', '\f', '\r':
		return true
	}
	return false
}
