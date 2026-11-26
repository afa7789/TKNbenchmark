// `./app lru`: see the "lru" section of SPEC.md.
package lru

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

import "../ioutil"

@(private = "file")
MAX_CAPACITY :: 1_000_000

@(private = "file")
OUTPUT_BUFFER_SIZE :: 64 * 1024

// Reads standard input, writes standard output and returns the exit status.
run :: proc() -> (exit_code: int) {
	input, read_err := ioutil.read_all(os.stdin)
	if read_err != nil {
		fmt.eprintln("lru: reading standard input:", read_err)
		return 1
	}
	defer delete(input)

	out: bufio.Writer
	bufio.writer_init(&out, os.to_writer(os.stdout), OUTPUT_BUFFER_SIZE)
	defer bufio.writer_destroy(&out)

	ok := simulate(string(input), bufio.writer_to_writer(&out))
	if flush_err := bufio.writer_flush(&out); flush_err != nil {
		fmt.eprintln("lru: writing standard output:", flush_err)
		return 1
	}
	return 0 if ok else 1
}

// Runs the commands in `input` (capacity line first) and writes their output
// to `w`. Keys and values held by the cache are slices of `input`.
@(private = "file")
simulate :: proc(input: string, w: io.Writer) -> (ok: bool) {
	rest := input
	header, _ := next_line(&rest)
	capacity, cap_ok := strconv.parse_int(strings.trim_space(header), 10)
	if !cap_ok || capacity < 1 || capacity > MAX_CAPACITY {
		fmt.eprintfln("lru: invalid capacity %q", header)
		return false
	}

	cache: Cache
	cache_init(&cache, capacity, strings.count(rest, "\n") + 1)
	defer cache_destroy(&cache)

	for line in next_line(&rest) {
		args := line
		command := next_token(&args)
		switch command {
		case "SET":
			key := next_token(&args)
			value := next_token(&args)
			cache_set(&cache, key, value)
		case "GET":
			key := next_token(&args)
			if value, hit := cache_get(&cache, key); hit {
				io.write_string(w, value)
			} else {
				io.write_string(w, "NULL")
			}
			io.write_byte(w, '\n')
		case "DEL":
			key := next_token(&args)
			io.write_string(w, "1\n" if cache_del(&cache, key) else "0\n")
		case "SIZE":
			io.write_int(w, cache_len(&cache))
			io.write_byte(w, '\n')
		case "":
		// Blank line: nothing to do.
		case:
			fmt.eprintfln("lru: unknown command %q", command)
		}
	}
	return true
}

// Pops the next line off `s`, without its terminator ("\n" or "\r\n").
// The last line may lack a terminator.
@(private = "file")
next_line :: proc(s: ^string) -> (line: string, ok: bool) {
	if len(s) == 0 {
		return "", false
	}
	if i := strings.index_byte(s^, '\n'); i >= 0 {
		line, s^ = s[:i], s[i + 1:]
	} else {
		line, s^ = s^, ""
	}
	return strings.trim_suffix(line, "\r"), true
}

// Pops the next space-separated token off `s`.
@(private = "file")
next_token :: proc(s: ^string) -> (token: string) {
	if i := strings.index_byte(s^, ' '); i >= 0 {
		token, s^ = s[:i], s[i + 1:]
	} else {
		token, s^ = s^, ""
	}
	return
}
