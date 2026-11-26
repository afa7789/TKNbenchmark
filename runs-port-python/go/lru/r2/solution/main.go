// Command app simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each later line is one of
// SET <key> <value>, GET <key>, DEL <key> or SIZE. See SPEC.md.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"
)

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run reads the capacity and commands from r and writes command output to w.
// Blank lines, unknown commands and commands missing arguments are ignored.
// An unparsable capacity line produces no output.
func run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(bufio.NewReaderSize(r, 1<<16))
	sc.Buffer(make([]byte, 0, 1<<16), 64<<20)
	out := bufio.NewWriterSize(w, 1<<16)

	if !sc.Scan() {
		return sc.Err()
	}
	capacity, ok := parseCapacity(sc.Bytes())
	if !ok {
		return nil
	}
	cache := NewCache(capacity)

	var num []byte
	for sc.Scan() {
		var f [3][]byte
		n := fields(sc.Bytes(), f[:])
		if n == 0 {
			continue
		}
		switch string(f[0]) {
		case "GET":
			if n < 2 {
				continue
			}
			if v, ok := cache.Get(f[1]); ok {
				out.WriteString(v)
			} else {
				out.WriteString("NULL")
			}
		case "SET":
			if n < 3 {
				continue
			}
			cache.Set(f[1], f[2])
			continue
		case "DEL":
			if n < 2 {
				continue
			}
			if cache.Delete(f[1]) {
				out.WriteByte('1')
			} else {
				out.WriteByte('0')
			}
		case "SIZE":
			num = strconv.AppendInt(num[:0], int64(cache.Len()), 10)
			out.Write(num)
		default:
			continue
		}
		out.WriteByte('\n')
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return out.Flush()
}

// parseCapacity parses the capacity line, tolerating surrounding whitespace.
// Values too large to represent are treated as unbounded.
func parseCapacity(line []byte) (int, bool) {
	n, err := strconv.Atoi(string(bytes.TrimSpace(line)))
	if errors.Is(err, strconv.ErrRange) {
		if n > 0 {
			return math.MaxInt, true
		}
		return n, true
	}
	return n, err == nil
}

// fields splits line on ASCII whitespace into at most len(dst) leading fields,
// storing them in dst and returning how many were found. Fields beyond
// len(dst) are ignored.
func fields(line []byte, dst [][]byte) int {
	n := 0
	i := 0
	for n < len(dst) {
		for i < len(line) && isSpace(line[i]) {
			i++
		}
		if i == len(line) {
			break
		}
		start := i
		for i < len(line) && !isSpace(line[i]) {
			i++
		}
		dst[n] = line[start:i]
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
