// wordfreq: reads standard input and prints the 10 most frequent words.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

TOP_N :: 10
CHUNK_SIZE :: 1 << 20

Entry :: struct {
	word:  string,
	count: int,
}

// Counts holds per-word frequencies. Keys are owned by the map.
Counts :: map[string]int

is_ascii_letter :: #force_inline proc "contextless" (b: byte) -> bool {
	return (b | 0x20) - 'a' < 26
}

// add_word increments the count for an already-lowercased word, cloning
// the key only on first insertion so the scratch buffer can be reused.
add_word :: proc(counts: ^Counts, word: []byte) {
	key := string(word)
	if count, ok := &counts[key]; ok {
		count^ += 1
		return
	}
	counts[strings.clone(key)] = 1
}

// count_words streams the file in chunks; a word spanning a chunk
// boundary is carried over in `word`.
count_words :: proc(f: ^os.File, counts: ^Counts) -> os.Error {
	buf := make([]byte, CHUNK_SIZE)
	defer delete(buf)

	word := make([dynamic]byte, 0, 64)
	defer delete(word)

	for {
		n, err := os.read(f, buf)
		for b in buf[:n] {
			if is_ascii_letter(b) {
				append(&word, b | 0x20)
			} else if len(word) > 0 {
				add_word(counts, word[:])
				clear(&word)
			}
		}
		if err == .EOF || (err == nil && n == 0) {
			break
		}
		if err != nil {
			return err
		}
	}
	if len(word) > 0 {
		add_word(counts, word[:])
	}
	return nil
}

entry_less :: proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// top_entries returns the n highest-ranked entries in rank order.
top_entries :: proc(counts: Counts, n: int, allocator := context.allocator) -> []Entry {
	entries := make([dynamic]Entry, 0, len(counts), context.temp_allocator)
	for word, count in counts {
		append(&entries, Entry{word, count})
	}
	slice.sort_by(entries[:], entry_less)
	k := min(n, len(entries))
	return slice.clone(entries[:k], allocator)
}

main :: proc() {
	counts := make(Counts)
	defer {
		for word in counts {
			delete(word)
		}
		delete(counts)
	}

	if err := count_words(os.stdin, &counts); err != nil {
		fmt.eprintln("wordfreq: error reading stdin:", os.error_string(err))
	}

	top := top_entries(counts, TOP_N)
	defer delete(top)

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for e in top {
		fmt.sbprintf(&sb, "%d %s\n", e.count, e.word)
	}
	os.write_string(os.stdout, strings.to_string(sb))
	free_all(context.temp_allocator)
}
