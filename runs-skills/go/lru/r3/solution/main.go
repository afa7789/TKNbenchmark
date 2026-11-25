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
	sc := bufio.NewScanner(bufio.NewReaderSize(r, 1<<16))
	sc.Buffer(make([]byte, 0, 1<<12), 1<<20)
	out := bufio.NewWriterSize(w, 1<<16)

	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return fmt.Errorf("read capacity: %w", err)
		}
		return errors.New("missing capacity")
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil || capacity < 1 {
		return fmt.Errorf("invalid capacity %q", sc.Bytes())
	}
	cache := lru.New(capacity)

	for sc.Scan() {
		if err := exec(cache, bytes.TrimRight(sc.Bytes(), "\r"), out); err != nil {
			return err
		}
	}
	if err := sc.Err(); err != nil {
		return fmt.Errorf("read commands: %w", err)
	}
	return out.Flush()
}

// exec applies a single command line to cache, writing any output to out.
// Blank or unrecognised lines are ignored.
func exec(cache *lru.Cache, line []byte, out *bufio.Writer) error {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	var err error
	switch string(cmd) {
	case "SET":
		key, value, _ := bytes.Cut(rest, []byte{' '})
		cache.Set(string(key), string(value))
	case "GET":
		// string(rest) in a map lookup does not allocate.
		if v, ok := cache.Get(string(rest)); ok {
			_, err = out.WriteString(v)
		} else {
			_, err = out.WriteString("NULL")
		}
		if err == nil {
			err = out.WriteByte('\n')
		}
	case "DEL":
		if cache.Delete(string(rest)) {
			_, err = out.WriteString("1\n")
		} else {
			_, err = out.WriteString("0\n")
		}
	case "SIZE":
		_, err = out.Write(strconv.AppendInt(out.AvailableBuffer(), int64(cache.Len()), 10))
		if err == nil {
			err = out.WriteByte('\n')
		}
	}
	if err != nil {
		return fmt.Errorf("write output: %w", err)
	}
	return nil
}
