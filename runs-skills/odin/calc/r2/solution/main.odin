package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

import "calc"

main :: proc() {
	data, err := os.read_entire_file(os.stdin, context.allocator)
	if err != nil {
		fmt.eprintln("calc: reading stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(data)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&w)
	out := bufio.writer_to_writer(&w)

	ev: calc.Evaluator
	calc.evaluator_init(&ev)
	defer calc.evaluator_destroy(&ev)

	num_buf: [32]byte
	src := string(data)
	for line in strings.split_iterator(&src, "\n") {
		if calc.is_blank(line) {
			continue
		}
		if value, eerr := calc.evaluate(&ev, line); eerr == .None {
			io.write_string(out, strconv.write_int(num_buf[:], value, 10))
		} else {
			io.write_string(out, "error")
		}
		io.write_byte(out, '\n')
	}
	bufio.writer_flush(&w)
}
