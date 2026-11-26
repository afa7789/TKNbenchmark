// Command app simulates an LRU cache driven by commands read from standard
// input. See SPEC.md for the protocol.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"lru/internal/lru"
)

const bufferSize = 1 << 16

func main() {
	out := bufio.NewWriterSize(os.Stdout, bufferSize)
	err := run(os.Stdin, out)
	if ferr := out.Flush(); err == nil {
		err = ferr
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "app:", err)
		os.Exit(1)
	}
}

// run reads the capacity header and then executes each command line.
func run(r io.Reader, w *bufio.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, bufferSize), 1<<30)
	if !sc.Scan() {
		return sc.Err()
	}
	capacity, err := strconv.Atoi(strings.TrimSpace(sc.Text()))
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

// execute applies one command line to the cache. Blank or unrecognised lines
// are ignored.
func execute(cache *lru.Cache[string, string], line []byte, w *bufio.Writer) {
	cmd, rest, hasArg := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !hasArg || !ok {
			return
		}
		cache.Set(string(key), string(value))
	case "GET":
		if !hasArg {
			return
		}
		if v, ok := cache.Get(string(rest)); ok {
			writeLine(w, v)
		} else {
			writeLine(w, "NULL")
		}
	case "DEL":
		if !hasArg {
			return
		}
		if cache.Delete(string(rest)) {
			writeLine(w, "1")
		} else {
			writeLine(w, "0")
		}
	case "SIZE":
		w.WriteString(strconv.Itoa(cache.Len()))
		w.WriteByte('\n')
	}
}

// writeLine writes s followed by a newline. Write errors are sticky in
// bufio.Writer and surface when the writer is flushed.
func writeLine(w *bufio.Writer, s string) {
	w.WriteString(s)
	w.WriteByte('\n')
}
