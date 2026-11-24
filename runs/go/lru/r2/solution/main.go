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
			return err
		}
		return nil // empty input: nothing to do
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil || capacity < 1 {
		return fmt.Errorf("invalid capacity %q", sc.Text())
	}
	cache := NewCache(capacity)

	for sc.Scan() {
		execute(cache, bytes.TrimRight(sc.Bytes(), "\r"), out)
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return out.Flush()
}

// execute applies one command line to the cache, writing any output to out.
// Blank or malformed lines are ignored.
func execute(c *Cache, line []byte, out *bufio.Writer) {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !ok {
			return
		}
		c.Set(string(key), string(value))
	case "GET":
		if v, ok := c.Get(string(rest)); ok {
			out.WriteString(v)
		} else {
			out.WriteString("NULL")
		}
		out.WriteByte('\n')
	case "DEL":
		if c.Delete(string(rest)) {
			out.WriteString("1\n")
		} else {
			out.WriteString("0\n")
		}
	case "SIZE":
		out.WriteString(strconv.Itoa(c.Len()))
		out.WriteByte('\n')
	}
}
