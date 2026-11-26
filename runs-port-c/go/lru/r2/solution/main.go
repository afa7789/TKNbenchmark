// Command lru simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each later line is one of
// SET <key> <value>, GET <key>, DEL <key> or SIZE.
package main

import (
	"bufio"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"
	"strings"
)

func main() {
	out := bufio.NewWriterSize(os.Stdout, 1<<16)
	if err := run(os.Stdin, out); err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
	if err := out.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

// run executes the command stream read from r, writing results to w.
func run(r io.Reader, w *bufio.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	// Keys and values are substrings of the single input string, so storing
	// them in the cache needs no per-entry allocation.
	input := string(data)

	first, rest, _ := strings.Cut(input, "\n")
	cache := NewCache(parseCapacity(first))

	for len(rest) > 0 {
		var line string
		line, rest, _ = strings.Cut(rest, "\n")
		line = strings.TrimSuffix(line, "\r")

		cmd, line := nextToken(line)
		switch cmd {
		case "SET":
			key, line := nextToken(line)
			value, _ := nextToken(line)
			if key != "" {
				cache.Set(key, value)
			}
		case "GET":
			key, _ := nextToken(line)
			if value, ok := cache.Get(key); ok {
				w.WriteString(value)
			} else {
				w.WriteString("NULL")
			}
			w.WriteByte('\n')
		case "DEL":
			key, _ := nextToken(line)
			if cache.Delete(key) {
				w.WriteString("1\n")
			} else {
				w.WriteString("0\n")
			}
		case "SIZE":
			w.Write(strconv.AppendInt(w.AvailableBuffer(), int64(cache.Len()), 10))
			w.WriteByte('\n')
		}
	}
	return nil
}

// nextToken skips leading spaces and splits off the next space-delimited token.
func nextToken(s string) (token, rest string) {
	s = strings.TrimLeft(s, " ")
	if i := strings.IndexByte(s, ' '); i >= 0 {
		return s[:i], s[i:]
	}
	return s, ""
}

// parseCapacity reads the leading decimal digits of s (after optional blanks),
// saturating at math.MaxUint32 and returning at least 1.
func parseCapacity(s string) int {
	s = strings.TrimLeft(s, " \t")
	var v uint64
	for i := 0; i < len(s) && s[i] >= '0' && s[i] <= '9'; i++ {
		v = min(v*10+uint64(s[i]-'0'), math.MaxUint32)
	}
	return int(max(v, 1))
}
