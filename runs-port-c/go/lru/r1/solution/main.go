// Command app simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each later line is one of
// SET <key> <value>, GET <key>, DEL <key> or SIZE. See SPEC.md.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"lru/internal/lru"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "lru: %v\n", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("read input: %w", err)
	}
	// One copy into a string lets keys and values be zero-copy substrings.
	input := string(data)

	first, rest := nextLine(input)
	capacity, ok := parseCapacity(first)
	if !ok {
		return nil // nothing to simulate
	}

	cache := lru.New(capacity, strings.Count(rest, "\n")+1)
	out := bufio.NewWriterSize(w, 64<<10)
	for rest != "" {
		var line string
		line, rest = nextLine(rest)
		execute(cache, line, out)
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("write output: %w", err)
	}
	return nil
}

// nextLine splits off the first line of s, without its "\n" or a trailing "\r".
func nextLine(s string) (line, rest string) {
	line, rest, _ = strings.Cut(s, "\n")
	return strings.TrimSuffix(line, "\r"), rest
}

// nextToken splits off the next space-delimited token of s; tok is empty if
// none remain.
func nextToken(s string) (tok, rest string) {
	s = strings.TrimLeft(s, " ")
	if i := strings.IndexByte(s, ' '); i >= 0 {
		return s[:i], s[i:]
	}
	return s, ""
}

// parseCapacity reads a positive decimal capacity from the first token.
func parseCapacity(line string) (int, bool) {
	tok, _ := nextToken(line)
	if tok == "" || len(tok) > 18 {
		return 0, false
	}
	for i := 0; i < len(tok); i++ {
		if tok[i] < '0' || tok[i] > '9' {
			return 0, false
		}
	}
	v, err := strconv.Atoi(tok)
	if err != nil || v == 0 {
		return 0, false
	}
	return v, true
}

// execute runs one command line. Blank, malformed and unknown commands are
// ignored.
func execute(cache *lru.Cache, line string, out *bufio.Writer) {
	cmd, rest := nextToken(line)
	switch cmd {
	case "GET":
		key, _ := nextToken(rest)
		if key == "" {
			return
		}
		if v, ok := cache.Get(key); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "SET":
		key, rest := nextToken(rest)
		value, _ := nextToken(rest)
		if key == "" || value == "" {
			return
		}
		cache.Set(key, value)
	case "DEL":
		key, _ := nextToken(rest)
		if key == "" {
			return
		}
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
}
