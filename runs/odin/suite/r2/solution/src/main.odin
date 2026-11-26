// suite: a command-line program with three independent subcommands
// (wordfreq, lru, calc). Each reads standard input and writes standard output.
package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"

USAGE :: "usage: app <wordfreq | lru | calc>"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln(USAGE)
		os.exit(2)
	}

	input, ok := read_all_stdin()
	if !ok {
		fmt.eprintln("error: failed to read standard input")
		os.exit(1)
	}

	out: bufio.Writer
	bufio.writer_init(&out, os.to_stream(os.stdout), 1 << 16)
	defer bufio.writer_destroy(&out)
	w := bufio.writer_to_writer(&out)

	switch os.args[1] {
	case "wordfreq":
		wordfreq(input, w)
	case "lru":
		lru(input, w)
	case "calc":
		calc(input, w)
	case:
		fmt.eprintln(USAGE)
		os.exit(2)
	}

	if bufio.writer_flush(&out) != nil {
		os.exit(1)
	}
}

// Reads all of standard input into a single buffer. Works for pipes as well as
// regular files, growing geometrically so large inputs stay linear-time.
read_all_stdin :: proc(allocator := context.allocator) -> (data: []byte, ok: bool) {
	buf := make([dynamic]byte, 1 << 20, allocator)
	total := 0
	for {
		if len(buf) - total < 1 << 16 {
			non_zero_resize(&buf, 2 * len(buf))
		}
		n, err := os.read(os.stdin, buf[total:])
		total += n
		if err == .EOF || (err == nil && n == 0) {
			break
		}
		if err != nil {
			delete(buf)
			return nil, false
		}
	}
	return buf[:total], true
}

write_int :: proc(w: io.Writer, v: i64) {
	digits: [32]byte
	io.write_string(w, strconv.write_int(digits[:], v, 10))
}

write_line :: proc(w: io.Writer, s: string) {
	io.write_string(w, s)
	io.write_byte(w, '\n')
}
