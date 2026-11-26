// `./app calc`: see the "calc" section of SPEC.md.
package calc

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "../ioutil"

// Reads standard input, writes standard output and returns the exit status.
//
// Every line of input is evaluated independently and its value (or `error`)
// is printed on its own line; blank lines produce no output.
run :: proc() -> (exit_code: int) {
	data, read_err := ioutil.read_all(os.stdin)
	if read_err != nil {
		fmt.eprintln("calc: reading standard input:", read_err)
		return 1
	}
	defer delete(data)

	out: bufio.Writer
	bufio.writer_init(&out, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&out)

	ev: Evaluator
	defer evaluator_destroy(&ev)

	num_buf: [32]byte
	input := string(data)
	for line in strings.split_iterator(&input, "\n") {
		if is_blank(line) {
			continue
		}
		if value, ok := evaluate(&ev, line); ok {
			bufio.writer_write_string(&out, strconv.write_int(num_buf[:], value, 10))
		} else {
			bufio.writer_write_string(&out, "error")
		}
		bufio.writer_write_byte(&out, '\n')
	}

	if err := bufio.writer_flush(&out); err != nil {
		fmt.eprintln("calc: writing standard output:", err)
		return 1
	}
	return 0
}

@(private = "file")
is_blank :: proc(line: string) -> bool {
	for c in transmute([]byte)line {
		if c != ' ' && c != '\t' {
			return false
		}
	}
	return true
}
