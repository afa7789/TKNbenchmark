// wordfreq: prints the 10 most frequent ASCII words read from standard input.
package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:slice"

TOP_N :: 10
READ_CHUNK :: 1 << 20

Entry :: struct {
	word:  string,
	count: int,
}

// Reads all of `f` into a single buffer, growing it in large chunks.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: [dynamic]byte, err: os.Error) {
	data = make([dynamic]byte, 0, READ_CHUNK, allocator) or_return
	for {
		if cap(data) - len(data) < READ_CHUNK {
			reserve(&data, 2 * cap(data)) or_return
		}
		start := len(data)
		resize(&data, cap(data)) or_return
		n, rerr := os.read(f, data[start:])
		resize(&data, start + n) or_return
		if rerr == .EOF || rerr == .Broken_Pipe || (rerr == nil && n == 0) {
			return data, nil
		}
		if rerr != nil {
			return data, rerr
		}
	}
}

is_letter :: #force_inline proc "contextless" (b: byte) -> bool {
	return (b | 0x20) - 'a' < 26
}

// Counts words in `text`, lowercasing it in place. Map keys are views into `text`.
count_words :: proc(text: []byte, counts: ^map[string]int) #no_bounds_check {
	i := 0
	n := len(text)
	for i < n {
		for i < n && !is_letter(text[i]) {
			i += 1
		}
		start := i
		for i < n && is_letter(text[i]) {
			text[i] |= 0x20
			i += 1
		}
		if i > start {
			counts[string(text[start:i])] += 1
		}
	}
}

entry_less :: proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

main :: proc() {
	data, err := read_all(os.stdin)
	defer delete(data)
	if err != nil {
		fmt.eprintln("wordfreq: reading stdin:", os.error_string(err))
		os.exit(1)
	}

	counts := make(map[string]int)
	defer delete(counts)
	count_words(data[:], &counts)

	entries := make([dynamic]Entry, 0, len(counts))
	defer delete(entries)
	for word, count in counts {
		append(&entries, Entry{word, count})
	}
	slice.sort_by(entries[:], entry_less)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_stream(os.stdout))
	defer bufio.writer_destroy(&w)
	out := bufio.writer_to_stream(&w)
	for e in entries[:min(TOP_N, len(entries))] {
		fmt.wprintf(out, "%d %s\n", e.count, e.word)
	}
	if ferr := bufio.writer_flush(&w); ferr != .None {
		os.exit(1)
	}
}
