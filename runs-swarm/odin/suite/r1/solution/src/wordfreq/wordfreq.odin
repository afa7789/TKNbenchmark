// `./app wordfreq`: see the "wordfreq" section of SPEC.md.
//
// Reads all of standard input, counts case-folded runs of ASCII letters and
// prints the TOP_N most frequent as `<count> <word>` lines, ordered by count
// descending, then word ascending.
package wordfreq

import "core:fmt"
import "core:os"
import "core:strings"

import "../ioutil"

@(private)
TOP_N :: 10

@(private)
Entry :: struct {
	word:  string,
	count: int,
}

// Reads standard input, writes standard output and returns the exit status.
run :: proc() -> (exit_code: int) {
	data, err := ioutil.read_all(os.stdin)
	defer delete(data)
	if err != nil {
		fmt.eprintln("wordfreq: reading standard input:", err)
		return 1
	}

	counts := count_words(data)
	defer delete(counts)

	top: [TOP_N]Entry
	n := top_entries(counts, top[:])

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	for e in top[:n] {
		strings.write_int(&b, e.count)
		strings.write_byte(&b, ' ')
		strings.write_string(&b, e.word)
		strings.write_byte(&b, '\n')
	}
	if _, werr := os.write_string(os.stdout, strings.to_string(b)); werr != nil {
		fmt.eprintln("wordfreq: writing standard output:", werr)
		return 1
	}
	return 0
}

// Lowercases every word of `data` in place and counts it. The map keys are
// slices of `data`, which must therefore outlive the returned map.
@(private)
count_words :: proc(data: []byte, allocator := context.allocator) -> map[string]int {
	counts := make(map[string]int, allocator)
	i := 0
	for i < len(data) {
		if !is_letter(data[i]) {
			i += 1
			continue
		}
		start := i
		for i < len(data) && is_letter(data[i]) {
			data[i] |= 0x20 // ASCII letters: setting bit 5 lowercases.
			i += 1
		}
		counts[string(data[start:i])] += 1
	}
	return counts
}

@(private)
is_letter :: #force_inline proc "contextless" (c: byte) -> bool {
	return (c | 0x20) - 'a' < 26
}

// Strict ranking order: higher count first, then lexicographically smaller word.
@(private)
ranks_before :: #force_inline proc(a, b: Entry) -> bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// Fills `top` with the best `len(top)` entries of `counts` in ranking order
// and returns how many were filled.
@(private)
top_entries :: proc(counts: map[string]int, top: []Entry) -> (n: int) {
	for word, count in counts {
		e := Entry{word, count}
		if n == len(top) {
			if !ranks_before(e, top[n - 1]) {
				continue
			}
		} else {
			n += 1
		}
		// Insertion step: shift worse entries down one slot.
		j := n - 1
		for j > 0 && ranks_before(e, top[j - 1]) {
			top[j] = top[j - 1]
			j -= 1
		}
		top[j] = e
	}
	return n
}
