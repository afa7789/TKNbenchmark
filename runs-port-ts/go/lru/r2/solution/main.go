// Command app simulates an LRU cache driven by commands read from stdin.
// See SPEC.md for the input format.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"math"
	"os"
	"strconv"

	"lru-sim/lru"
)

func main() {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "app: reading stdin:", err)
		os.Exit(1)
	}
	w := bufio.NewWriterSize(os.Stdout, 1<<16)
	run(input, w)
	if err := w.Flush(); err != nil {
		fmt.Fprintln(os.Stderr, "app: writing stdout:", err)
		os.Exit(1)
	}
}

// run executes the command script in input and writes the results to w.
func run(input []byte, w *bufio.Writer) {
	first, rest, _ := bytes.Cut(input, []byte{'\n'})
	capacity, ok := parseLeadingInt(first)
	if !ok || capacity < 1 {
		return
	}
	cache := lru.New(capacity)

	for len(rest) > 0 {
		var line []byte
		line, rest, _ = bytes.Cut(rest, []byte{'\n'})
		line = bytes.TrimSuffix(line, []byte{'\r'})
		if len(line) == 0 {
			continue
		}
		cmd, args, hasArgs := bytes.Cut(line, []byte{' '})
		switch string(cmd) {
		case "SET":
			key, value, ok := bytes.Cut(args, []byte{' '})
			if ok {
				cache.SetBytes(key, value)
			}
		case "GET":
			if hasArgs {
				if v, ok := cache.GetBytes(args); ok {
					w.WriteString(v)
				} else {
					w.WriteString("NULL")
				}
				w.WriteByte('\n')
			}
		case "DEL":
			if hasArgs {
				if cache.DeleteBytes(args) {
					w.WriteString("1\n")
				} else {
					w.WriteString("0\n")
				}
			}
		case "SIZE":
			w.Write(strconv.AppendInt(w.AvailableBuffer(), int64(cache.Len()), 10))
			w.WriteByte('\n')
		default:
			// Unknown commands are ignored.
		}
	}
}

// parseLeadingInt parses an optionally signed decimal integer prefix of b,
// after skipping leading whitespace and ignoring any trailing characters.
// Values too large for an int saturate.
func parseLeadingInt(b []byte) (int, bool) {
	i := 0
	for i < len(b) && isSpace(b[i]) {
		i++
	}
	neg := false
	if i < len(b) && (b[i] == '+' || b[i] == '-') {
		neg = b[i] == '-'
		i++
	}
	start := i
	n := 0
	for ; i < len(b) && b[i] >= '0' && b[i] <= '9'; i++ {
		d := int(b[i] - '0')
		if n > (math.MaxInt-d)/10 {
			n = math.MaxInt
		} else {
			n = n*10 + d
		}
	}
	if i == start {
		return 0, false
	}
	if neg {
		n = -n
	}
	return n, true
}

// isSpace reports whether c is whitespace when the input is read as Latin-1.
func isSpace(c byte) bool {
	switch c {
	case ' ', '\t', '\n', '\v', '\f', '\r', 0xA0:
		return true
	}
	return false
}
