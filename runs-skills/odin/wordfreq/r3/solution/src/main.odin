// wordfreq: print the 10 most frequent ASCII words read from standard input.
package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:slice"

TOP_N :: 10

Entry :: struct {
	word:  string,
	count: int,
}

// Orders by count descending, then by word ascending (byte order).
entry_less :: proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// Lowercases ASCII letters in place and counts each maximal run of letters.
// Map keys are views into `data`, which must outlive the returned map.
count_words :: proc(data: []byte, allocator := context.allocator) -> map[string]int {
	counts := make(map[string]int, 1024, allocator)
	start := -1
	#no_bounds_check for i in 0 ..< len(data) {
		c := data[i]
		lower := c | 0x20
		if lower >= 'a' && lower <= 'z' {
			data[i] = lower
			if start < 0 {
				start = i
			}
		} else if start >= 0 {
			counts[string(data[start:i])] += 1
			start = -1
		}
	}
	if start >= 0 {
		counts[string(data[start:])] += 1
	}
	return counts
}

// Reads `f` until EOF. Unlike `os.read_entire_file_from_file`, this does not
// trust the reported file size, which for pipes is only the buffered amount.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([]byte, 1 << 20, allocator) or_return
	total := 0
	for {
		if total == len(buf) {
			grown, aerr := make([]byte, 2 * len(buf), allocator)
			if aerr != nil {
				delete(buf, allocator)
				return nil, aerr
			}
			copy(grown, buf)
			delete(buf, allocator)
			buf = grown
		}
		n, rerr := os.read(f, buf[total:])
		total += n
		if rerr == .EOF || (rerr == nil && n == 0) {
			break
		}
		if rerr != nil {
			delete(buf, allocator)
			return nil, rerr
		}
	}
	return buf[:total], nil
}

// Returns the `n` highest-ranked entries in order.
top_entries :: proc(counts: map[string]int, n: int, allocator := context.allocator) -> [dynamic]Entry {
	entries := make([dynamic]Entry, 0, len(counts), allocator)
	for word, count in counts {
		append(&entries, Entry{word, count})
	}
	slice.sort_by(entries[:], entry_less)
	resize(&entries, min(n, len(entries)))
	return entries
}

main :: proc() {
	data, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("wordfreq: failed to read stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(data)

	counts := count_words(data)
	defer delete(counts)

	top := top_entries(counts, TOP_N)
	defer delete(top)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_stream(os.stdout))
	defer bufio.writer_destroy(&w)
	for e in top {
		fmt.wprintf(bufio.writer_to_stream(&w), "%d %s\n", e.count, e.word)
	}
	bufio.writer_flush(&w)
}
