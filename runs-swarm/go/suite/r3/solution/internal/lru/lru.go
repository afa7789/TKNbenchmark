// Package lru simulates an LRU cache driven by commands read from its input.
//
// See the lru section of SPEC.md for the exact input and output formats.
package lru

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"strconv"
)

// MaxCapacity is the largest capacity accepted on the first input line.
const MaxCapacity = 1_000_000

// maxLine bounds the length of a single input line. Well-formed commands are
// far shorter; the limit only guards against unbounded buffering.
const maxLine = 1 << 20

// Run reads the whole lru input from r and writes the results to w.
// w is buffered by the caller, which flushes it after Run returns.
//
// The first line holds the capacity; every later line is one command.
// Blank lines and unrecognised commands are ignored.
func Run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64<<10), maxLine)

	if !sc.Scan() {
		return sc.Err() // empty input: nothing to do
	}
	capacity, err := parseCapacity(sc.Bytes())
	if err != nil {
		return err
	}
	cache := NewCache(capacity)

	var out []byte // reply to the current command, reused across lines
	for sc.Scan() {
		out = execute(cache, trimCR(sc.Bytes()), out[:0])
		if len(out) == 0 {
			continue
		}
		if _, err := w.Write(out); err != nil {
			return err
		}
	}
	return sc.Err()
}

// execute runs one command line against cache and appends its reply, if any,
// to out. Malformed or unknown commands produce no reply.
func execute(cache *Cache, line, out []byte) []byte {
	cmd, args := splitToken(line)
	switch string(cmd) {
	case "SET":
		key, rest := splitToken(args)
		value, _ := splitToken(rest)
		if len(key) > 0 && len(value) > 0 {
			cache.Set(string(key), string(value))
		}
	case "GET":
		if key, _ := splitToken(args); len(key) > 0 {
			if v, ok := cache.Get(string(key)); ok {
				out = append(out, v...)
			} else {
				out = append(out, "NULL"...)
			}
			out = append(out, '\n')
		}
	case "DEL":
		if key, _ := splitToken(args); len(key) > 0 {
			if cache.Delete(string(key)) {
				out = append(out, "1\n"...)
			} else {
				out = append(out, "0\n"...)
			}
		}
	case "SIZE":
		out = strconv.AppendInt(out, int64(cache.Len()), 10)
		out = append(out, '\n')
	}
	return out
}

func parseCapacity(line []byte) (int, error) {
	text := string(bytes.TrimSpace(line))
	c, err := strconv.Atoi(text)
	if err != nil || c < 1 || c > MaxCapacity {
		return 0, fmt.Errorf("invalid capacity %q: want an integer in [1, %d]", text, MaxCapacity)
	}
	return c, nil
}

// splitToken returns the first space-separated token of b and the remainder
// after the separating space.
func splitToken(b []byte) (token, rest []byte) {
	token, rest, _ = bytes.Cut(b, []byte{' '})
	return token, rest
}

func trimCR(b []byte) []byte {
	return bytes.TrimSuffix(b, []byte{'\r'})
}
