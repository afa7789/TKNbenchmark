// Package wordfreq implements `app wordfreq`, which prints the 10 most frequent words read from standard input.
// See the "wordfreq" section of SPEC.md.
package wordfreq

import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"

// TOP_N is the maximum number of words reported.
TOP_N :: 10

// READ_CHUNK is the size of each read from standard input.
READ_CHUNK :: 256 * 1024

Entry :: struct {
	word:  string,
	count: int,
}

// Counter accumulates case-folded word counts. Words are interned in `arena`,
// so the map keys stay valid independently of the input buffer.
Counter :: struct {
	counts:  map[string]int,
	arena:   virtual.Arena,
	// A word cut off by the end of a read chunk, carried over to the next one.
	partial: [dynamic]byte,
}

// run is the entry point of the `wordfreq` subcommand.
run :: proc() {
	c: Counter
	counter_init(&c)
	defer counter_destroy(&c)

	count_stream(&c, os.stdin)

	top: [TOP_N]Entry
	n := top_entries(c.counts, top[:])
	write_entries(top[:n])
}

counter_init :: proc(c: ^Counter) {
	c.counts = make(map[string]int, 1 << 12)
	c.partial = make([dynamic]byte, 0, 64)
	_ = virtual.arena_init_growing(&c.arena)
}

counter_destroy :: proc(c: ^Counter) {
	delete(c.counts)
	delete(c.partial)
	virtual.arena_destroy(&c.arena)
}

// count_stream tokenizes everything readable from `f`. Read errors are
// treated like end of input: whatever was read so far is counted.
count_stream :: proc(c: ^Counter, f: ^os.File) {
	buf := make([]byte, READ_CHUNK)
	defer delete(buf)

	for {
		n, err := os.read(f, buf)
		if n > 0 {
			count_chunk(c, buf[:n])
		}
		if err != nil || n == 0 {
			break
		}
	}
	if len(c.partial) > 0 {
		add_word(c, c.partial[:])
		clear(&c.partial)
	}
}

// count_chunk lowercases `chunk` in place and counts every word in it. A word
// touching the end of the chunk may continue in the next one, so it is kept in
// `c.partial` instead of being counted.
count_chunk :: proc(c: ^Counter, chunk: []byte) {
	i := 0

	// Finish a word carried over from the previous chunk.
	if len(c.partial) > 0 {
		for i < len(chunk) && is_letter(chunk[i]) {
			i += 1
		}
		lower_in_place(chunk[:i])
		append(&c.partial, ..chunk[:i])
		if i == len(chunk) {
			return
		}
		add_word(c, c.partial[:])
		clear(&c.partial)
	}

	for i < len(chunk) {
		for i < len(chunk) && !is_letter(chunk[i]) {
			i += 1
		}
		start := i
		for i < len(chunk) && is_letter(chunk[i]) {
			i += 1
		}
		if start == i {
			break
		}
		word := chunk[start:i]
		lower_in_place(word)
		if i == len(chunk) {
			append(&c.partial, ..word)
		} else {
			add_word(c, word)
		}
	}
}

// add_word increments the count of the already-lowercased `word`, interning
// it on first sight.
add_word :: proc(c: ^Counter, word: []byte) {
	key_ptr, value_ptr, just_inserted, _ := map_entry(&c.counts, string(word))
	if just_inserted {
		key_ptr^ = strings.clone(string(word), virtual.arena_allocator(&c.arena))
	}
	value_ptr^ += 1
}

@(require_results)
is_letter :: #force_inline proc "contextless" (b: byte) -> bool {
	return (b | 0x20) - 'a' < 26
}

lower_in_place :: #force_inline proc "contextless" (word: []byte) {
	for &b in word {
		b |= 0x20
	}
}

// ranks_before reports whether `a` is ordered before `b`: higher count first,
// then word in ascending byte order.
@(require_results)
ranks_before :: proc "contextless" (a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// top_entries fills `out` with the highest-ranked entries of `counts`, in rank
// order, and returns how many were written. Runs in O(len(counts) * len(out)).
@(require_results)
top_entries :: proc(counts: map[string]int, out: []Entry) -> int {
	n := 0
	for word, count in counts {
		e := Entry{word, count}
		if n == len(out) {
			if !ranks_before(e, out[n - 1]) {
				continue
			}
		} else {
			n += 1
		}
		// Insertion step: shift lower-ranked entries down to make room.
		j := n - 1
		for j > 0 && ranks_before(e, out[j - 1]) {
			out[j] = out[j - 1]
			j -= 1
		}
		out[j] = e
	}
	return n
}

write_entries :: proc(entries: []Entry) {
	if len(entries) == 0 {
		return
	}
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	num_buf: [32]byte
	for e in entries {
		strings.write_string(&sb, strconv.write_int(num_buf[:], i64(e.count), 10))
		strings.write_byte(&sb, ' ')
		strings.write_string(&sb, e.word)
		strings.write_byte(&sb, '\n')
	}
	_, _ = os.write(os.stdout, sb.buf[:])
}
