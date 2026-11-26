// Package wordfreq prints the 10 most frequent words read from standard input.
// See the "wordfreq" section of SPEC.md.
package wordfreq

import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"

// TOP_N is the maximum number of words printed.
TOP_N :: 10

// READ_CHUNK_SIZE is how many bytes of standard input are processed at a time.
READ_CHUNK_SIZE :: 1 << 20

// Word_Count pairs a lowercase word with the number of times it occurred.
Word_Count :: struct {
	word:  string,
	count: int,
}

// Counter tallies lowercase words. Keys are owned by `arena`, so the whole table is freed at once.
Counter :: struct {
	counts: map[string]int,
	arena:  virtual.Arena,
}

counter_init :: proc(c: ^Counter) -> virtual.Allocator_Error {
	virtual.arena_init_growing(&c.arena) or_return
	c.counts = make(map[string]int)
	return nil
}

counter_destroy :: proc(c: ^Counter) {
	delete(c.counts)
	virtual.arena_destroy(&c.arena)
}

// counter_add counts one occurrence of `word`, which must already be lowercase.
// `word` may point into a transient buffer: it is copied the first time it is seen.
counter_add :: proc(c: ^Counter, word: []byte) {
	key_ptr, value_ptr, just_inserted, err := map_entry(&c.counts, string(word))
	if err != nil {
		return
	}
	if just_inserted {
		key_ptr^ = strings.clone(string(word), virtual.arena_allocator(&c.arena))
	}
	value_ptr^ += 1
}

// count_stream reads `f` to the end, counting every word in it.
// A word split across two reads is reassembled in a carry buffer.
count_stream :: proc(c: ^Counter, f: ^os.File) {
	buf := make([]byte, READ_CHUNK_SIZE)
	defer delete(buf)
	carry: [dynamic]byte
	defer delete(carry)

	for {
		n, err := os.read(f, buf)
		chunk := buf[:n]

		// Start of the word in progress within `chunk`, or -1 between words.
		// A word carried over from the previous read continues at the start of this chunk.
		start := 0 if len(carry) > 0 else -1
		for &b, i in chunk {
			if is_letter(b) {
				b |= 0x20 // ASCII lowercase.
				if start < 0 {
					start = i
				}
			} else if start >= 0 {
				word := chunk[start:i]
				if len(carry) > 0 {
					append(&carry, ..word)
					counter_add(c, carry[:])
					clear(&carry)
				} else {
					counter_add(c, word)
				}
				start = -1
			}
		}
		if start >= 0 {
			append(&carry, ..chunk[start:])
		}

		if err != nil {
			break
		}
	}

	if len(carry) > 0 {
		counter_add(c, carry[:])
	}
}

is_letter :: #force_inline proc "contextless" (b: byte) -> bool {
	return (b | 0x20) - 'a' < 26
}

// ranks_before reports whether `a` is listed before `b`: higher count first, then word ascending.
ranks_before :: proc(a, b: Word_Count) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// top_words writes the highest-ranked words into `out`, best first, and returns how many it wrote.
top_words :: proc(c: ^Counter, out: []Word_Count) -> int {
	n := 0
	for word, count in c.counts {
		entry := Word_Count{word, count}
		if n == len(out) && !ranks_before(entry, out[n - 1]) {
			continue
		}
		// Insertion into the sorted prefix, dropping the last entry when full.
		i := min(n, len(out) - 1)
		for i > 0 && ranks_before(entry, out[i - 1]) {
			out[i] = out[i - 1]
			i -= 1
		}
		out[i] = entry
		n = min(n + 1, len(out))
	}
	return n
}

// run is the entry point for `app wordfreq`. It reads standard input, writes standard output,
// and returns normally so that the process exits with status 0.
run :: proc() {
	counter: Counter
	if err := counter_init(&counter); err != nil {
		fmt.eprintln("wordfreq: out of memory:", err)
		return
	}
	defer counter_destroy(&counter)

	count_stream(&counter, os.stdin)

	top: [TOP_N]Word_Count
	n := top_words(&counter, top[:])

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for entry in top[:n] {
		fmt.sbprintf(&sb, "%d %s\n", entry.count, entry.word)
	}
	os.write_string(os.stdout, strings.to_string(sb))
}
