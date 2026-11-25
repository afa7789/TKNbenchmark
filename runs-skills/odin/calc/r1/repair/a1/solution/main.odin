// calc: reads one expression per line from stdin and prints its value or `error`.
package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

import "calc"

// Reads `f` until EOF. Unlike os.read_entire_file, this does not trust the
// reported file size, which for pipes on macOS is only the bytes currently
// buffered and would silently truncate the input.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, 64 * 1024, allocator) or_return
	defer if err != nil {
		delete(buf)
	}
	chunk: [64 * 1024]byte
	for {
		n, rerr := os.read(f, chunk[:])
		append(&buf, ..chunk[:n]) or_return
		if rerr == .EOF || rerr == .Broken_Pipe || (rerr == nil && n == 0) {
			break
		}
		if rerr != nil {
			return nil, rerr
		}
	}
	return buf[:], nil
}

main :: proc() {
	data, rerr := read_all(os.stdin)
	if rerr != nil {
		fmt.eprintln("calc: reading stdin:", os.error_string(rerr))
		os.exit(1)
	}
	defer delete(data)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&w)
	out := bufio.writer_to_writer(&w)

	ev: calc.Evaluator
	defer calc.evaluator_destroy(&ev)

	buf: [32]byte
	text := string(data)
	// Split on '\n' only: a '\r' is outside the grammar and must yield `error`.
	for line in strings.split_iterator(&text, "\n") {
		if len(strings.trim(line, " \t")) == 0 {
			continue
		}
		if value, err := calc.evaluate(&ev, line); err == .None {
			io.write_string(out, strconv.write_int(buf[:], value, 10))
		} else {
			io.write_string(out, "error")
		}
		io.write_byte(out, '\n')
	}
	bufio.writer_flush(&w)
}
