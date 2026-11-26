package main

// entry is a word and its number of occurrences.
type entry struct {
	word  string
	count int
}

// ranksBefore reports whether a ranks before b: higher count first, then
// lexicographically smaller word.
func ranksBefore(a, b entry) bool {
	if a.count != b.count {
		return a.count > b.count
	}
	return a.word < b.word
}

// top returns up to n entries from counts, best-ranked first.
func top(counts map[string]int, n int) []entry {
	if n <= 0 {
		return nil
	}
	out := make([]entry, 0, n)
	for word, count := range counts {
		e := entry{word, count}
		if len(out) == n {
			if !ranksBefore(e, out[n-1]) {
				continue
			}
			out = out[:n-1]
		}
		// Insertion into the small sorted slice.
		out = append(out, e)
		pos := len(out) - 1
		for pos > 0 && ranksBefore(e, out[pos-1]) {
			out[pos] = out[pos-1]
			pos--
		}
		out[pos] = e
	}
	return out
}
