// Command app simulates an LRU cache driven by commands on standard input.
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

const nullReply = "NULL"

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "read stdin:", err)
		os.Exit(1)
	}
	w := bufio.NewWriterSize(os.Stdout, 64<<10)
	if err := run(input, w); err != nil {
		fmt.Fprintln(os.Stderr, "write stdout:", err)
		os.Exit(1)
	}
	if err := w.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "write stdout:", err)
		os.Exit(1)
	}
}

// run executes the command script in input, writing one reply per line to w.
// Malformed lines and unknown commands are ignored. If the capacity line is
// invalid, nothing is written.
func run(input []byte, w *bufio.Writer) error {
	first, rest, _ := bytes.Cut(input, []byte{'\n'})
	capacity, ok := parseCapacity(first)
	if !ok {
		return nil
	}
	cache := lru.New(capacity)
	var num []byte

	for len(rest) > 0 {
		var line []byte
		line, rest, _ = bytes.Cut(rest, []byte{'\n'})
		line = bytes.TrimSuffix(line, []byte{'\r'})
		if len(line) == 0 {
			continue
		}

		command, arg, _ := bytes.Cut(line, []byte{' '})
		switch string(command) {
		case "SET":
			key, value, found := bytes.Cut(arg, []byte{' '})
			if found {
				cache.Set(string(key), string(value))
			}
			continue
		case "GET":
			if v, ok := cache.GetBytes(arg); ok {
				w.WriteString(v)
			} else {
				w.WriteString(nullReply)
			}
		case "DEL":
			if cache.DeleteBytes(arg) {
				w.WriteByte('1')
			} else {
				w.WriteByte('0')
			}
		case "SIZE":
			num = strconv.AppendInt(num[:0], int64(cache.Len()), 10)
			w.Write(num)
		default:
			continue
		}
		if err := w.WriteByte('\n'); err != nil {
			return err
		}
	}
	return nil
}

// parseCapacity reads a leading integer from line with the leniency of
// JavaScript's parseInt: leading whitespace is skipped, an optional sign is
// accepted, and anything after the digits is ignored. It reports false when
// no digits are found or the value is less than 1. Values too large to
// represent saturate, which is equivalent to an unbounded cache.
func parseCapacity(line []byte) (int, bool) {
	i := 0
	for i < len(line) && isSpace(line[i]) {
		i++
	}
	negative := false
	if i < len(line) && (line[i] == '+' || line[i] == '-') {
		negative = line[i] == '-'
		i++
	}
	const limit = 1 << 40
	n, digits := 0, 0
	for ; i < len(line) && '0' <= line[i] && line[i] <= '9'; i++ {
		if n < limit {
			n = n*10 + int(line[i]-'0')
		}
		digits++
	}
	if digits == 0 || negative || n < 1 {
		return 0, false
	}
	return n, true
}

// isSpace reports whether b (interpreted as Latin-1) is JavaScript whitespace.
func isSpace(b byte) bool {
	switch b {
	case '\t', '\n', '\v', '\f', '\r', ' ', 0xA0:
		return true
	}
	return false
}
