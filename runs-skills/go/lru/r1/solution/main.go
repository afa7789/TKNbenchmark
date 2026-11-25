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
	out := bufio.NewWriterSize(os.Stdout, 1<<16)
	err := run(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run reads the capacity and commands from r and writes command results to w.
func run(r io.Reader, w *bufio.Writer) error {
	sc := bufio.NewScanner(bufio.NewReaderSize(r, 1<<16))
	sc.Buffer(make([]byte, 0, 4096), 1<<20)

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

	cache := lru.New[string, string](capacity)
	for sc.Scan() {
		cmd, rest, _ := bytes.Cut(bytes.TrimRight(sc.Bytes(), "\r"), []byte{' '})
		switch string(cmd) {
		case "SET":
			key, value, ok := bytes.Cut(rest, []byte{' '})
			if ok {
				cache.Set(string(key), string(value))
			}
		case "GET":
			if v, ok := cache.Get(string(rest)); ok {
				w.WriteString(v)
			} else {
				w.WriteString("NULL")
			}
			w.WriteByte('\n')
		case "DEL":
			if cache.Delete(string(rest)) {
				w.WriteString("1\n")
			} else {
				w.WriteString("0\n")
			}
		case "SIZE":
			w.Write(strconv.AppendInt(w.AvailableBuffer(), int64(cache.Len()), 10))
			w.WriteByte('\n')
		}
	}
	if err := sc.Err(); err != nil {
		return fmt.Errorf("read commands: %w", err)
	}
	return nil
}
