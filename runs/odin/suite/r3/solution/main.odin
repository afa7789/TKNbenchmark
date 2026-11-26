// suite: a command-line program bundling three independent stdin→stdout tools.
//
//	./app wordfreq   top-10 word frequencies
//	./app lru        LRU cache simulator
//	./app calc       64-bit integer expression evaluator
package suite

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:strconv"

USAGE :: "usage: app (wordfreq | lru | calc) < input\n"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprint(USAGE)
		os.exit(2)
	}

	input, err := read_all_stdin()
	if err != nil {
		fmt.eprintfln("app: reading standard input: %v", err)
		os.exit(1)
	}

	out: bufio.Writer
	bufio.writer_init(&out, os.to_stream(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&out)

	switch os.args[1] {
	case "wordfreq":
		wordfreq_run(input, &out)
	case "lru":
		lru_run(string(input), &out)
	case "calc":
		calc_run(string(input), &out)
	case:
		fmt.eprint(USAGE)
		os.exit(2)
	}

	if ferr := bufio.writer_flush(&out); ferr != nil {
		fmt.eprintfln("app: writing standard output: %v", ferr)
		os.exit(1)
	}
}

// read_all_stdin reads standard input to EOF. Standard input is usually a pipe, whose
// size is unknown, so it is read in large chunks into a buffer that doubles as needed.
read_all_stdin :: proc(allocator := context.allocator) -> (data: []byte, err: os.Error) {
	CHUNK :: 1 << 20
	buf := make([]byte, 4 * CHUNK, allocator) or_return
	n := 0
	for {
		if len(buf) - n < CHUNK {
			grown := make([]byte, 2 * len(buf), allocator) or_return
			copy(grown, buf[:n])
			delete(buf, allocator)
			buf = grown
		}
		read, rerr := os.read(os.stdin, buf[n:])
		n += read
		if rerr == .EOF || (rerr == nil && read == 0) {
			break
		}
		if rerr != nil {
			delete(buf, allocator)
			return nil, rerr
		}
	}
	return buf[:n], nil
}

// write_line writes s followed by a newline.
write_line :: proc(w: ^bufio.Writer, s: string) {
	bufio.writer_write_string(w, s)
	bufio.writer_write_byte(w, '\n')
}

// write_int writes the decimal form of v without a newline.
write_int :: proc(w: ^bufio.Writer, v: i64) {
	digits: [32]byte
	bufio.writer_write_string(w, strconv.write_int(digits[:], v, 10))
}

// split_line removes the first line from s and returns it without its terminator
// (a trailing '\r' is dropped as well). ok is false once s is exhausted.
split_line :: proc(s: ^string) -> (line: string, ok: bool) {
	if len(s^) == 0 {
		return "", false
	}
	end := len(s^)
	next := end
	for i in 0 ..< len(s^) {
		if s[i] == '\n' {
			end, next = i, i + 1
			break
		}
	}
	line = s[:end]
	s^ = s[next:]
	if len(line) > 0 && line[len(line) - 1] == '\r' {
		line = line[:len(line) - 1]
	}
	return line, true
}
