package suite

import "core:bufio"

TOP_WORDS :: 10

Word_Count :: struct {
	word:  string,
	count: int,
}

// wordfreq_run prints the TOP_WORDS most frequent words of data, most frequent first,
// ties broken by ascending byte order. A word is a maximal run of ASCII letters,
// compared case-insensitively. data is lowercased in place so words can borrow it.
wordfreq_run :: proc(data: []byte, out: ^bufio.Writer) {
	counts := make(map[string]int, 1 << 14)
	defer delete(counts)

	i := 0
	n := len(data)
	for i < n {
		for i < n && !is_letter(data[i]) {
			i += 1
		}
		start := i
		for i < n && is_letter(data[i]) {
			data[i] |= 0x20 // for ASCII letters, setting bit 5 lowercases
			i += 1
		}
		if i > start {
			counts[string(data[start:i])] += 1
		}
	}

	// Select the top entries with an insertion-sorted fixed array: O(distinct words).
	top: [TOP_WORDS]Word_Count
	held := 0
	for word, count in counts {
		e := Word_Count{word, count}
		if held == TOP_WORDS && !ranks_before(e, top[held - 1]) {
			continue
		}
		j := min(held, TOP_WORDS - 1)
		for j > 0 && ranks_before(e, top[j - 1]) {
			top[j] = top[j - 1]
			j -= 1
		}
		top[j] = e
		held = min(held + 1, TOP_WORDS)
	}

	for e in top[:held] {
		write_int(out, i64(e.count))
		bufio.writer_write_byte(out, ' ')
		write_line(out, e.word)
	}
}

// ranks_before orders by count descending, then word ascending.
ranks_before :: proc(a, b: Word_Count) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

is_letter :: #force_inline proc "contextless" (b: byte) -> bool {
	return (b | 0x20) - 'a' < 26
}
