package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

import "calc"

// read_all reads f until EOF. Unlike os.read_entire_file it does not trust
// file_size, which for a pipe reports only the bytes currently buffered.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, 64 * 1024, allocator) or_return
	defer if err != nil {
		delete(buf)
	}
	chunk: [64 * 1024]byte
	for {
		n, rerr := os.read(f, chunk[:])
		append(&buf, ..chunk[:n]) or_return
		if rerr == .EOF || rerr == .Broken_Pipe {
			break
		}
		if rerr != nil {
			return nil, rerr
		}
		if n == 0 {
			break
		}
	}
	return buf[:], nil
}

main :: proc() {
	data, err := read_all(os.stdin, context.allocator)
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
