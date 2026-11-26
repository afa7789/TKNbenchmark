// suite: a single binary bundling three independent stdin→stdout tools.
//
//   app wordfreq   top-10 word frequencies
//   app lru        LRU cache simulator
//   app calc       64-bit integer expression evaluator
package suite

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:strconv"

OUTPUT_BUFFER_SIZE :: 64 * 1024
READ_CHUNK_SIZE    :: 1 << 20

main :: proc() {
	if len(os.args) < 2 {
		usage()
		os.exit(2)
	}

	input, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("error reading standard input:", err)
		os.exit(1)
	}

	out: bufio.Writer
	bufio.writer_init(&out, os.to_stream(os.stdout), OUTPUT_BUFFER_SIZE)
	defer bufio.writer_destroy(&out)

	switch os.args[1] {
	case "wordfreq":
		wordfreq(input, &out)
	case "lru":
		lru(input, &out)
	case "calc":
		calc(input, &out)
	case:
		usage()
		os.exit(2)
	}

	if ferr := bufio.writer_flush(&out); ferr != nil {
		fmt.eprintln("error writing standard output:", ferr)
		os.exit(1)
	}
}

usage :: proc() {
	fmt.eprintln("usage: app (wordfreq | lru | calc) < input")
}

// Reads a file to EOF in large chunks; works for pipes where the size is unknown.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, READ_CHUNK_SIZE, allocator)
	for {
		if cap(buf) - len(buf) < READ_CHUNK_SIZE {
			reserve(&buf, 2 * cap(buf))
		}
		start := len(buf)
		resize(&buf, cap(buf))
		n, rerr := os.read(f, buf[start:])
		resize(&buf, start + n)
		if rerr == .EOF || rerr == .Broken_Pipe || (rerr == nil && n == 0) {
			return buf[:], nil
		}
		if rerr != nil {
			return buf[:], rerr
		}
	}
}

// Writes a signed integer in decimal.
write_int :: proc(w: ^bufio.Writer, v: i64) {
	digits: [32]byte
	bufio.writer_write_string(w, strconv.write_int(digits[:], v, 10))
}

write_line :: proc(w: ^bufio.Writer, s: string) {
	bufio.writer_write_string(w, s)
	bufio.writer_write_byte(w, '\n')
}
