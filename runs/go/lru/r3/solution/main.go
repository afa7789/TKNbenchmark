// Command app simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each following line is one of
// SET <key> <value>, GET <key>, DEL <key>, or SIZE.
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
	sc := bufio.NewScanner(bufio.NewReaderSize(r, 1<<16))
	sc.Buffer(make([]byte, 0, 1<<16), 1<<20)
	out := bufio.NewWriterSize(w, 1<<16)

	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return fmt.Errorf("reading capacity: %w", err)
		}
		return nil // empty input: nothing to do
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil || capacity < 1 {
		return fmt.Errorf("invalid capacity %q", sc.Text())
	}
	cache := lru.New(capacity)

	for sc.Scan() {
		if err := execute(cache, bytes.TrimRight(sc.Bytes(), "\r"), out); err != nil {
			return err
		}
	}
	if err := sc.Err(); err != nil {
		return fmt.Errorf("reading input: %w", err)
	}
	return out.Flush()
}

// execute applies one command line to cache, writing any output to out.
// Blank or unrecognized lines are ignored.
func execute(cache *lru.Cache, line []byte, out *bufio.Writer) error {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !ok {
			return nil
		}
		cache.Set(string(key), string(value))
		return nil
	case "GET":
		v, ok := cache.Get(string(rest))
		if !ok {
			v = "NULL"
		}
		out.WriteString(v)
	case "DEL":
		if cache.Delete(string(rest)) {
			out.WriteByte('1')
		} else {
			out.WriteByte('0')
		}
	case "SIZE":
		out.WriteString(strconv.Itoa(cache.Len()))
	default:
		return nil
	}
	return out.WriteByte('\n')
}
