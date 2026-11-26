// Command app simulates an LRU cache driven by commands read from stdin.
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

	header, rest, ok := nextLine(input)
	if !ok {
		return nil
	}
	capacity, err := parseCapacity(header)
	if err != nil {
		return err
	}

	out := bufio.NewWriterSize(w, 1<<16)
	cache := lru.New[string, []byte](capacity)

	for {
		var line []byte
		if line, rest, ok = nextLine(rest); !ok {
			break
		}
		if len(line) == 0 {
			continue
		}
		command, args, _ := bytes.Cut(line, []byte{' '})
		switch string(command) {
		case "SET":
			key, value, found := bytes.Cut(args, []byte{' '})
			if found {
				cache.Set(string(key), value)
			}
		case "GET":
			if value, hit := cache.Get(string(keyArg(line, args))); hit {
				out.Write(value)
			} else {
				out.WriteString("NULL")
			}
			out.WriteByte('\n')
		case "DEL":
			if cache.Delete(string(keyArg(line, args))) {
				out.WriteString("1\n")
			} else {
				out.WriteString("0\n")
			}
		case "SIZE":
			out.Write(strconv.AppendInt(out.AvailableBuffer(), int64(cache.Len()), 10))
			out.WriteByte('\n')
		default:
			// Unknown commands are ignored; the spec defines no output for them.
		}
	}

	if err := out.Flush(); err != nil {
		return fmt.Errorf("writing output: %w", err)
	}
	return nil
}

// keyArg returns the key operand of a single-argument command. A bare command
// with no operand uses the whole line as its key, matching the reference
// implementation.
func keyArg(line, args []byte) []byte {
	if bytes.IndexByte(line, ' ') < 0 {
		return line
	}
	return args
}

// nextLine splits off the first line of data, stripping the "\n" terminator
// and an optional preceding "\r". It reports false when data is exhausted.
func nextLine(data []byte) (line, rest []byte, ok bool) {
	if len(data) == 0 {
		return nil, nil, false
	}
	line, rest, _ = bytes.Cut(data, []byte{'\n'})
	line = bytes.TrimSuffix(line, []byte{'\r'})
	return line, rest, true
}

// parseCapacity parses the header line: leading decimal digits (optionally
// signed) after surrounding whitespace, like JavaScript's parseInt.
func parseCapacity(header []byte) (int, error) {
	s := bytes.TrimSpace(header)
	end := 0
	if end < len(s) && (s[end] == '+' || s[end] == '-') {
		end++
	}
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	n, err := strconv.Atoi(string(s[:end]))
	if err != nil || n < 1 {
		return 0, errors.New("capacity must be a positive integer, got " + strconv.Quote(string(header)))
	}
	return n, nil
}
