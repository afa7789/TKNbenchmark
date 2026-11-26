// Command app simulates an LRU cache driven by commands on standard input.
//
// The first line holds the capacity; each later line is one of
// "SET <key> <value>", "GET <key>", "DEL <key>" or "SIZE". Results are
// written to standard output, one per line.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"

	"lru/lru"
)

const bufferSize = 1 << 16

func main() {
	out := bufio.NewWriterSize(os.Stdout, bufferSize)
	err := run(os.Stdin, out)
	if flushErr := out.Flush(); err == nil {
		err = flushErr
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "lru:", err)
		os.Exit(1)
	}
}

func run(r io.Reader, w *bufio.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, bufferSize), bufio.MaxScanTokenSize*16)

	if !sc.Scan() {
		return sc.Err()
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil {
		return fmt.Errorf("invalid capacity: %w", err)
	}
	if capacity < 1 {
		return errors.New("capacity must be positive")
	}

	cache := lru.New[string, string](capacity)
	for sc.Scan() {
		execute(cache, sc.Bytes(), w)
	}
	return sc.Err()
}

// execute applies one command line to cache. Blank or unrecognised lines are
// ignored, as are commands missing their arguments.
func execute(cache *lru.Cache[string, string], line []byte, w *bufio.Writer) {
	cmd, args, hasArgs := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(args, []byte{' '})
		if !hasArgs || !ok {
			return
		}
		cache.Set(string(key), string(value))
	case "GET":
		if !hasArgs {
			return
		}
		if value, ok := cache.Get(string(args)); ok {
			w.WriteString(value)
		} else {
			w.WriteString("NULL")
		}
		w.WriteByte('\n')
	case "DEL":
		if !hasArgs {
			return
		}
		if cache.Delete(string(args)) {
			w.WriteString("1\n")
		} else {
			w.WriteString("0\n")
		}
	case "SIZE":
		w.Write(strconv.AppendInt(w.AvailableBuffer(), int64(cache.Len()), 10))
		w.WriteByte('\n')
	}
}
