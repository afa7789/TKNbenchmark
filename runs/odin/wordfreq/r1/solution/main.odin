// wordfreq: prints the 10 most frequent ASCII words read from standard input.
package wordfreq

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:slice"

TOP_N :: 10

Entry :: struct {
	word:  string,
	count: int,
}

// read_all reads standard input to EOF using large chunks, which is much
// faster than the small fixed buffer the stdlib uses for unsized streams.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	CHUNK :: 1 << 20
	buf := make([dynamic]byte, 0, CHUNK, allocator) or_return
	for {
		if cap(buf) - len(buf) < CHUNK {
			reserve(&buf, 2 * cap(buf)) or_return
		}
		start := len(buf)
		resize(&buf, cap(buf)) or_return
		n, rerr := os.read(f, buf[start:])
		resize(&buf, start + n)
		if rerr != nil {
			if rerr == .EOF || rerr == .Broken_Pipe {
				return buf[:], nil
			}
			return buf[:], rerr
		}
		if n == 0 {
			return buf[:], nil
		}
	}
}

// count_words lowercases `data` in place and counts each maximal run of ASCII
// letters. Map keys are slices into `data`, so it must outlive the map.
count_words :: proc(data: []byte, counts: ^map[string]int) {
	i := 0
	n := len(data)
	for i < n {
		// Skip separators.
		for i < n && !is_letter(data[i]) {
			i += 1
		}
		start := i
		for i < n && is_letter(data[i]) {
			data[i] |= 0x20 // ASCII fold to lowercase.
			i += 1
		}
		if i > start {
			word := string(data[start:i])
			counts[word] += 1
		}
	}
}

@(require_results)
is_letter :: #force_inline proc "contextless" (b: byte) -> bool {
	return (b | 0x20) - 'a' < 26
}

// entry_less orders by count descending, then word ascending (byte order).
entry_less :: proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

main :: proc() {
	data, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("wordfreq: failed to read stdin:", err)
	}

	counts := make(map[string]int)
	count_words(data, &counts)

	entries := make([dynamic]Entry, 0, len(counts))
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
	io.flush(out)
}
