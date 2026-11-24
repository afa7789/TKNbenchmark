// wordfreq: print the 10 most frequent ASCII words read from standard input.
package wordfreq

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

// Counts lowercase-folded words, carrying partial words across chunk boundaries.
Counter :: struct {
	counts:  map[string]int,
	pending: [dynamic]byte,
}

counter_init :: proc(c: ^Counter) {
	c.counts = make(map[string]int, 1024)
	c.pending = make([dynamic]byte, 0, 64)
}

counter_destroy :: proc(c: ^Counter) {
	for word in c.counts {
		delete(word)
	}
	delete(c.counts)
	delete(c.pending)
}

@(private)
add_word :: proc(c: ^Counter, word: []byte) {
	key := string(word)
	if ptr, ok := &c.counts[key]; ok {
		ptr^ += 1
		return
	}
	c.counts[strings.clone(key)] = 1
}

@(private)
flush_pending :: proc(c: ^Counter) {
	if len(c.pending) > 0 {
		add_word(c, c.pending[:])
		clear(&c.pending)
	}
}

// Feeds a chunk of raw bytes; the chunk is lowercased in place.
counter_feed :: proc(c: ^Counter, chunk: []byte) {
	start := -1
	for i in 0 ..< len(chunk) {
		b := chunk[i]
		switch b {
		case 'A' ..= 'Z':
			chunk[i] = b + ('a' - 'A')
			fallthrough
		case 'a' ..= 'z':
			if start < 0 {
				start = i
			}
		case:
			if start >= 0 {
				if len(c.pending) > 0 {
					append(&c.pending, ..chunk[start:i])
					flush_pending(c)
				} else {
					add_word(c, chunk[start:i])
				}
				start = -1
			} else {
				flush_pending(c)
			}
		}
	}
	if start >= 0 {
		append(&c.pending, ..chunk[start:])
	}
}

counter_finish :: proc(c: ^Counter) {
	flush_pending(c)
}

entry_less :: proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

main :: proc() {
	counter: Counter
	counter_init(&counter)
	defer counter_destroy(&counter)

	buf := make([]byte, READ_CHUNK)
	defer delete(buf)

	for {
		n, err := os.read(os.stdin, buf)
		if n > 0 {
			counter_feed(&counter, buf[:n])
		}
		if err != nil {
			if err != .EOF && err != .Broken_Pipe {
				fmt.eprintln("wordfreq: read error:", err)
			}
			break
		}
		if n == 0 {
			break
		}
	}
	counter_finish(&counter)

	entries := make([dynamic]Entry, 0, len(counter.counts))
	defer delete(entries)
	for word, count in counter.counts {
		append(&entries, Entry{word, count})
	}
	slice.sort_by(entries[:], entry_less)

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	for e in entries[:min(TOP_N, len(entries))] {
		fmt.sbprintf(&sb, "%d %s\n", e.count, e.word)
	}
	os.write(os.stdout, sb.buf[:])
}
