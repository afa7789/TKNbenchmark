// calc: reads one expression per line from stdin and prints its value or `error`.
package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

import "calc"

main :: proc() {
	data, rerr := os.read_entire_file(os.stdin, context.allocator)
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
	for line in strings.split_lines_iterator(&text) {
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
