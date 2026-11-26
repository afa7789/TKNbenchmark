package suite

import "core:bufio"
import "core:slice"

TOP_WORDS :: 10

Word_Count :: struct {
	word:  string,
	count: int,
}

// Prints the TOP_WORDS most frequent words in `input`, folding ASCII letters
// to lowercase. `input` is lowercased in place so that words can be slices of it.
wordfreq :: proc(input: []byte, out: ^bufio.Writer) {
	counts := make(map[string]int, 1 << 14)
	defer delete(counts)

	i, n := 0, len(input)
	for i < n {
		for i < n && !is_ascii_letter(input[i]) {
			i += 1
		}
		start := i
		for i < n && is_ascii_letter(input[i]) {
			input[i] |= 0x20 // ASCII letters: setting bit 5 lowercases
			i += 1
		}
		if i > start {
			counts[string(input[start:i])] += 1
		}
	}

	top := top_words(counts)
	for wc in top {
		write_int(out, i64(wc.count))
		bufio.writer_write_byte(out, ' ')
		write_line(out, wc.word)
	}
}

// Orders by count descending, then word ascending.
word_count_less :: proc(a, b: Word_Count) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// Selects the best TOP_WORDS entries in a single pass with a small sorted buffer.
top_words :: proc(counts: map[string]int) -> []Word_Count {
	@(static) buf: [TOP_WORDS]Word_Count
	n := 0
	for word, count in counts {
		wc := Word_Count{word, count}
		if n == TOP_WORDS && !word_count_less(wc, buf[n - 1]) {
			continue
		}
		j := n if n < TOP_WORDS else n - 1
		for j > 0 && word_count_less(wc, buf[j - 1]) {
			buf[j] = buf[j - 1]
			j -= 1
		}
		buf[j] = wc
		if n < TOP_WORDS {
			n += 1
		}
	}
	assert(slice.is_sorted_by(buf[:n], word_count_less))
	return buf[:n]
}

is_ascii_letter :: #force_inline proc(c: byte) -> bool {
	return (c | 0x20) - 'a' < 26
}
