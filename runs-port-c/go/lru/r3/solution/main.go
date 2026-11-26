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

const maxCapacity = 1_000_000

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("read: %w", err)
	}
	if len(data) == 0 {
		return nil
	}
	// One conversion up front lets every key and value be a zero-copy
	// substring of the input.
	input := string(data)

	first, rest := nextLine(input)
	capacity := parseCapacity(first)
	lines := strings.Count(rest, "\n") + 1
	cache := lru.New(capacity, lines)

	out := bufio.NewWriterSize(w, 64<<10)
	for len(rest) > 0 {
		var line string
		line, rest = nextLine(rest)
		execute(cache, out, line)
	}
	if err := out.Flush(); err != nil {
		return fmt.Errorf("write: %w", err)
	}
	return nil
}

// nextLine splits off the first line of s, dropping the "\n" terminator and
// a trailing "\r".
func nextLine(s string) (line, rest string) {
	line, rest, _ = strings.Cut(s, "\n")
	return strings.TrimSuffix(line, "\r"), rest
}

// parseCapacity reads a leading integer the way C's strtol does (optional
// leading whitespace and sign, then digits, ignoring anything after) and
// clamps it to [1, maxCapacity].
func parseCapacity(s string) int {
	s = strings.TrimLeft(s, " \t\v\f\r")
	neg := false
	if s != "" && (s[0] == '+' || s[0] == '-') {
		neg = s[0] == '-'
		s = s[1:]
	}
	n := 0
	for i := 0; i < len(s) && '0' <= s[i] && s[i] <= '9'; i++ {
		n = min(n*10+int(s[i]-'0'), maxCapacity+1) // saturate to avoid overflow
	}
	if neg {
		n = -n
	}
	return max(1, min(n, maxCapacity))
}

// nextToken returns the next space-delimited token of s and the remainder.
func nextToken(s string) (tok, rest string) {
	s = strings.TrimLeft(s, " ")
	if i := strings.IndexByte(s, ' '); i >= 0 {
		return s[:i], s[i:]
	}
	return s, ""
}

// execute runs one command line. Malformed or unknown commands are ignored.
func execute(c *lru.Cache, out *bufio.Writer, line string) {
	cmd, line := nextToken(line)
	if cmd == "SIZE" {
		out.Write(strconv.AppendInt(out.AvailableBuffer(), int64(c.Len()), 10))
		out.WriteByte('\n')
		return
	}
	key, line := nextToken(line)
	if key == "" {
		return
	}
	switch cmd {
	case "GET":
		if v, ok := c.Get(key); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if c.Delete(key) {
			out.WriteString("1\n")
		} else {
			out.WriteString("0\n")
		}
	case "SET":
		if value, _ := nextToken(line); value != "" {
			c.Set(key, value)
		}
	}
}
