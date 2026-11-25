package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

main :: proc() {
	data, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("lru: failed to read stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(data)

	out := strings.builder_make()
	defer strings.builder_destroy(&out)

	run(string(data), &out)

	if _, werr := os.write_string(os.stdout, strings.to_string(out)); werr != nil {
		fmt.eprintln("lru: failed to write stdout:", os.error_string(werr))
		os.exit(1)
	}
}

// Reads `f` until EOF. Unlike `os.read_entire_file`, this does not trust the
// reported file size, which for a pipe on macOS is only the buffered amount.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, 1 << 20, allocator) or_return
	defer if err != nil {
		delete(buf)
	}
	chunk: [64 * 1024]byte
	for {
		n, rerr := os.read(f, chunk[:])
		append(&buf, ..chunk[:n]) or_return
		if rerr == .EOF || (rerr == nil && n == 0) {
			break
		}
		if rerr != nil {
			return nil, rerr
		}
	}
	return buf[:], nil
}

// Executes the command script in `input`, appending results to `out`.
// Keys and values stored in the cache are views into `input`.
run :: proc(input: string, out: ^strings.Builder) {
	s := input
	first, has_first := strings.split_lines_iterator(&s)
	if !has_first {
		return
	}
	capacity, ok := strconv.parse_int(strings.trim_space(first))
	if !ok || capacity < 1 {
		fmt.eprintln("lru: invalid capacity")
		os.exit(1)
	}

	cache: Lru
	lru_init(&cache, capacity)
	defer lru_destroy(&cache)

	for raw in strings.split_lines_iterator(&s) {
		line := strings.trim_right(raw, "\r")
		cmd, rest := cut(line)
		switch cmd {
		case "SET":
			key, value := cut(rest)
			lru_set(&cache, key, value)
		case "GET":
			key, _ := cut(rest)
			if value, hit := lru_get(&cache, key); hit {
				strings.write_string(out, value)
			} else {
				strings.write_string(out, "NULL")
			}
			strings.write_byte(out, '\n')
		case "DEL":
			key, _ := cut(rest)
			strings.write_byte(out, '1' if lru_del(&cache, key) else '0')
			strings.write_byte(out, '\n')
		case "SIZE":
			strings.write_int(out, lru_size(&cache))
			strings.write_byte(out, '\n')
		}
	}
}

// Splits `s` at the first space.
cut :: proc(s: string) -> (head, tail: string) {
	if i := strings.index_byte(s, ' '); i >= 0 {
		return s[:i], s[i + 1:]
	}
	return s, ""
}
