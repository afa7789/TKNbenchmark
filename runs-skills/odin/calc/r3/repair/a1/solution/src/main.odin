package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Reads `f` until EOF. `os.read_entire_file` trusts the reported file size,
// which for a pipe on macOS is only the currently buffered byte count, so
// large piped input would be truncated.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	out := make([dynamic]byte, 0, 64 * 1024, allocator) or_return
	chunk: [64 * 1024]byte
	for {
		n, rerr := os.read(f, chunk[:])
		append(&out, ..chunk[:n]) or_return
		if rerr == .EOF || rerr == .Broken_Pipe || (rerr == nil && n == 0) {
			break
		}
		if rerr != nil {
			delete(out)
			return nil, rerr
		}
	}
	return out[:], nil
}

main :: proc() {
	input, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("calc: reading stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(input)

	out := strings.builder_make()
	defer strings.builder_destroy(&out)

	ev: Evaluator
	defer evaluator_destroy(&ev)

	buf: [32]u8
	text := strings.trim_suffix(string(input), "\n")
	// Split on "\n" only: a "\r" is not part of the grammar and must yield "error".
	for line in strings.split_iterator(&text, "\n") {
		if len(strings.trim(line, " \t")) == 0 {
			continue
		}
		if value, eval_err := evaluate(&ev, line); eval_err == .None {
			strings.write_string(&out, strconv.write_int(buf[:], value, 10))
		} else {
			strings.write_string(&out, "error")
		}
		strings.write_byte(&out, '\n')
	}

	if _, werr := os.write(os.stdout, out.buf[:]); werr != nil {
		os.exit(1)
	}
}
