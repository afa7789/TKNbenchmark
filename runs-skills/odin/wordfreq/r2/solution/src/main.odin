// wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

TOP_N :: 10
READ_CHUNK :: 1 << 16

Entry :: struct {
	word:  string,
	count: int,
}

// Reads all of `f` into a single buffer, growing in large chunks so pipes are cheap to drain.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: [dynamic]byte, err: os.Error) {
	data = make([dynamic]byte, 0, READ_CHUNK, allocator) or_return
	for {
		if cap(data) - len(data) < READ_CHUNK {
			reserve(&data, 2 * cap(data)) or_return
		}
		old_len := len(data)
		resize(&data, cap(data)) or_return
		n, rerr := os.read(f, data[old_len:])
		resize(&data, old_len + n)
		if rerr == .EOF || rerr == .Broken_Pipe || (rerr == nil && n == 0) {
			return data, nil
		}
		if rerr != nil {
			return data, rerr
		}
	}
}

// Counts words in `text`, lowercasing it in place; the map keys are views into `text`.
count_words :: proc(text: []byte, counts: ^map[string]int) {
	i := 0
	n := len(text)
	#no_bounds_check for i < n {
		c := text[i]
		if !is_letter(c) {
			i += 1
			continue
		}
		start := i
		for i < n && is_letter(text[i]) {
			text[i] |= 0x20 // ASCII letters: setting bit 5 lowercases
			i += 1
		}
		counts[string(text[start:i])] += 1
	}
}

is_letter :: #force_inline proc(c: byte) -> bool {
	return (c | 0x20) - 'a' < 26
}

entry_less :: proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

main :: proc() {
	data, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("wordfreq: reading stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(data)

	counts := make(map[string]int)
	defer delete(counts)
	count_words(data[:], &counts)

	entries := make([dynamic]Entry, 0, len(counts))
	defer delete(entries)
	for word, count in counts {
		append(&entries, Entry{word, count})
	}
	slice.sort_by(entries[:], entry_less)

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	for e in entries[:min(TOP_N, len(entries))] {
		fmt.sbprintf(&b, "%d %s\n", e.count, e.word)
	}
	os.write_string(os.stdout, strings.to_string(b))
}
