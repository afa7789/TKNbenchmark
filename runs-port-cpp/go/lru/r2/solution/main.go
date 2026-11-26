// Command app simulates an LRU cache: it reads a capacity and a stream of
// commands from stdin and writes command results to stdout. See SPEC.md.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"

	"lrusim/lru"
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
	line, rest, ok := nextLine(input)
	if !ok {
		return nil
	}
	cache := lru.New(parseCapacity(line))

	out := bufio.NewWriterSize(w, 1<<16)
	for {
		line, rest, ok = nextLine(rest)
		if !ok {
			break
		}
		execute(cache, line, out)
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}

// nextLine splits off the first '\n'-terminated line of text, tolerating a
// missing final newline and a stray '\r' before the newline.
func nextLine(text []byte) (line, rest []byte, ok bool) {
	if len(text) == 0 {
		return nil, nil, false
	}
	line, rest, _ = bytes.Cut(text, []byte{'\n'})
	line = bytes.TrimSuffix(line, []byte{'\r'})
	return line, rest, true
}

// nextToken returns the next space-delimited token of s and the remainder.
func nextToken(s []byte) (token, rest []byte) {
	s = bytes.TrimLeft(s, " ")
	if i := bytes.IndexByte(s, ' '); i >= 0 {
		return s[:i], s[i:]
	}
	return s, nil
}

// parseCapacity reads the leading decimal digits of the first token.
// A missing or out-of-range number yields 0.
func parseCapacity(line []byte) int {
	token, _ := nextToken(line)
	end := 0
	for end < len(token) && token[end] >= '0' && token[end] <= '9' {
		end++
	}
	n, err := strconv.Atoi(string(token[:end]))
	if err != nil {
		return 0
	}
	return n
}

func execute(cache *lru.Cache, line []byte, out *bufio.Writer) {
	command, args := nextToken(line)
	switch string(command) {
	case "SET":
		key, args := nextToken(args)
		value, _ := nextToken(args)
		if len(key) > 0 && len(value) > 0 {
			cache.Set(key, value)
		}
	case "GET":
		key, _ := nextToken(args)
		if value, ok := cache.Get(key); ok {
			out.WriteString(value)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		key, _ := nextToken(args)
		if cache.Delete(key) {
			out.WriteString("1\n")
		} else {
			out.WriteString("0\n")
		}
	case "SIZE":
		var buf [20]byte
		out.Write(strconv.AppendInt(buf[:0], int64(cache.Len()), 10))
		out.WriteByte('\n')
	}
	// Blank or unrecognised lines produce no output.
}
