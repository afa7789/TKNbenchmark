package main

import "core:io"
import "core:slice"

TOP_WORDS :: 10

FNV_OFFSET :: u64(0xcbf29ce484222325)
FNV_PRIME :: u64(0x100000001b3)

@(private = "file")
Word_Entry :: struct {
	hash:  u64,
	word:  string, // slice of the (lowercased) input buffer; empty means unused slot
	count: int,
}

// Open-addressing hash table from word to count. Keys borrow from the input
// buffer, so counting allocates nothing per word.
@(private = "file")
Word_Table :: struct {
	slots: []Word_Entry,
	used:  int,
}

@(private = "file")
table_init :: proc(t: ^Word_Table, capacity: int) {
	t.slots = make([]Word_Entry, capacity)
	t.used = 0
}

@(private = "file")
table_destroy :: proc(t: ^Word_Table) {
	delete(t.slots)
}

@(private = "file")
table_add :: proc(t: ^Word_Table, word: string, hash: u64) {
	if 2 * (t.used + 1) > len(t.slots) {
		table_grow(t)
	}
	mask := u64(len(t.slots) - 1)
	i := hash & mask
	for {
		e := &t.slots[i]
		if len(e.word) == 0 {
			e^ = {hash, word, 1}
			t.used += 1
			return
		}
		if e.hash == hash && e.word == word {
			e.count += 1
			return
		}
		i = (i + 1) & mask
	}
}

@(private = "file")
table_grow :: proc(t: ^Word_Table) {
	old := t.slots
	t.slots = make([]Word_Entry, 2 * len(old))
	mask := u64(len(t.slots) - 1)
	for e in old {
		if len(e.word) == 0 {
			continue
		}
		i := e.hash & mask
		for len(t.slots[i].word) != 0 {
			i = (i + 1) & mask
		}
		t.slots[i] = e
	}
	delete(old)
}

// Prints the TOP_WORDS most frequent words: count descending, then word ascending.
// Lowercases `input` in place.
wordfreq :: proc(input: []byte, w: io.Writer) {
	table: Word_Table
	table_init(&table, 1 << 12)
	defer table_destroy(&table)

	i, n := 0, len(input)
	for i < n {
		c := input[i]
		if !is_ascii_letter(c) {
			i += 1
			continue
		}
		start := i
		hash := FNV_OFFSET
		for i < n {
			c = input[i]
			if !is_ascii_letter(c) {
				break
			}
			c |= 0x20 // ASCII letters: setting bit 5 lowercases
			input[i] = c
			hash = (hash ~ u64(c)) * FNV_PRIME
			i += 1
		}
		table_add(&table, string(input[start:i]), hash)
	}

	entries := make([dynamic]Word_Entry, 0, table.used)
	defer delete(entries)
	for e in table.slots {
		if len(e.word) != 0 {
			append(&entries, e)
		}
	}

	ranks_before :: proc(a, b: Word_Entry) -> bool {
		if a.count != b.count {
			return a.count > b.count
		}
		return a.word < b.word
	}
	slice.sort_by(entries[:], ranks_before)

	for e in entries[:min(len(entries), TOP_WORDS)] {
		write_int(w, i64(e.count))
		io.write_byte(w, ' ')
		write_line(w, e.word)
	}
}

@(private = "file")
is_ascii_letter :: #force_inline proc(c: byte) -> bool {
	return (c | 0x20) - 'a' < 26
}
