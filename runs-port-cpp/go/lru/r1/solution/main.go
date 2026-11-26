// Command app simulates an LRU cache driven by commands read from stdin.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w io.Writer) error {
	input, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	out := bufio.NewWriterSize(w, 1<<16)

	line, rest, _ := bytes.Cut(input, []byte{'\n'})
	cache := NewCache(parseCapacity(trim(line)))

	var num []byte
	for len(rest) > 0 {
		line, rest, _ = bytes.Cut(rest, []byte{'\n'})
		cmd, args := nextToken(trim(line))
		switch string(cmd) {
		case "SET":
			key, args := nextToken(args)
			value, _ := nextToken(args)
			cache.Set(key, value)
		case "GET":
			key, _ := nextToken(args)
			if v, ok := cache.Get(key); ok {
				out.WriteString(v)
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
			num = strconv.AppendInt(num[:0], int64(cache.Len()), 10)
			num = append(num, '\n')
			out.Write(num)
		}
	}
	return out.Flush()
}

// parseCapacity reads the leading decimal digits of s. A missing or
// out-of-range number yields 0.
func parseCapacity(s []byte) int {
	end := 0
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	n, err := strconv.ParseInt(string(s[:end]), 10, 0)
	if err != nil {
		return 0
	}
	return int(n)
}

// trim strips leading spaces/tabs and trailing spaces, tabs and carriage returns.
func trim(s []byte) []byte {
	s = bytes.TrimRight(s, " \t\r")
	return bytes.TrimLeft(s, " \t")
}

// nextToken splits off the next space-separated token from s.
func nextToken(s []byte) (tok, rest []byte) {
	tok, rest, _ = bytes.Cut(s, []byte{' '})
	return tok, rest
}
