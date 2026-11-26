// Command app simulates an LRU cache: it reads a capacity and a stream of
// SET/GET/DEL/SIZE commands from stdin and writes results to stdout.
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
	line, rest, ok := nextLine(input)
	if !ok {
		return nil
	}
	cache := lru.New(parseCapacity(line))

	out := bufio.NewWriterSize(w, 1<<16)
	for len(rest) > 0 {
		line, rest, _ = nextLine(rest)
		cmd, args := nextToken(line)
		switch string(cmd) {
		case "SET":
			key, args := nextToken(args)
			value, _ := nextToken(args)
			cache.Set(key, value)
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
			out.Write(strconv.AppendInt(out.AvailableBuffer(), int64(cache.Len()), 10))
			out.WriteByte('\n')
		}
	}
	return out.Flush()
}

// nextLine splits off the first line of data, dropping the terminator and
// any trailing '\r'. It reports false when data is empty.
func nextLine(data []byte) (line, rest []byte, ok bool) {
	if len(data) == 0 {
		return nil, nil, false
	}
	line, rest, _ = bytes.Cut(data, []byte{'\n'})
	return bytes.TrimSuffix(line, []byte{'\r'}), rest, true
}

// nextToken splits off the next space-delimited token.
func nextToken(s []byte) (token, rest []byte) {
	token, rest, _ = bytes.Cut(s, []byte{' '})
	return token, rest
}

// parseCapacity reads the leading decimal digits of s, ignoring anything
// after them.
func parseCapacity(s []byte) int {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			break
		}
		n = n*10 + int(c-'0')
	}
	return n
}
