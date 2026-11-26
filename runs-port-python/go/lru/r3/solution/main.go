// Command app simulates an LRU cache driven by commands read from standard
// input. See SPEC.md for the input format.
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

// run executes the command stream from r and writes the results to w.
func run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(bufio.NewReaderSize(r, 1<<16))
	sc.Buffer(make([]byte, 0, 1<<16), 1<<20)

	if !sc.Scan() {
		return sc.Err()
	}
	first := bytes.TrimSpace(sc.Bytes())
	if len(first) == 0 {
		return nil
	}
	capacity, err := strconv.Atoi(string(first))
	if err != nil {
		return fmt.Errorf("invalid capacity %q", first)
	}

	cache := NewCache(capacity)
	out := bufio.NewWriterSize(w, 1<<16)
	var num []byte

	for sc.Scan() {
		fields := bytes.Fields(sc.Bytes())
		if len(fields) == 0 {
			continue
		}
		switch string(fields[0]) {
		case "GET":
			if len(fields) < 2 {
				continue
			}
			if v, ok := cache.Get(fields[1]); ok {
				out.WriteString(v)
			} else {
				out.WriteString("NULL")
			}
			out.WriteByte('\n')
		case "SET":
			if len(fields) < 3 {
				continue
			}
			cache.Set(fields[1], fields[2])
		case "DEL":
			if len(fields) < 2 {
				continue
			}
			if cache.Delete(fields[1]) {
				out.WriteString("1\n")
			} else {
				out.WriteString("0\n")
			}
		case "SIZE":
			num = strconv.AppendInt(num[:0], int64(cache.Len()), 10)
			num = append(num, '\n')
			out.Write(num)
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return out.Flush()
}
