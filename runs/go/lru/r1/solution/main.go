// Command app simulates an LRU cache driven by commands on standard input.
// See SPEC.md for the input format.
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
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64*1024), 1<<20)
	out := bufio.NewWriterSize(w, 64*1024)

	var cache *Cache
	for sc.Scan() {
		line := bytes.TrimRight(sc.Bytes(), "\r")
		if cache == nil {
			s := string(bytes.TrimSpace(line))
			if s == "" {
				continue
			}
			capacity, err := strconv.Atoi(s)
			if err != nil || capacity < 1 {
				return fmt.Errorf("invalid capacity %q", s)
			}
			cache = NewCache(capacity)
			continue
		}
		execute(cache, line, out)
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return out.Flush()
}

// execute applies one command line to the cache, writing any output to out.
// Malformed or unknown commands are ignored.
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
		// string(rest) in a map index does not allocate.
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
