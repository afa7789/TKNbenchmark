// Package lru simulates an LRU cache driven by commands read from standard input.
// See the "lru" section of SPEC.md.
package lru

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

import "../input"

// run is the entry point for `app lru`. It reads standard input, writes standard output,
// and returns normally so that the process exits with status 0.
run :: proc() {
	data, err := input.read_all(os.stdin)
	if err != nil {
		fmt.eprintln("lru: failed to read standard input:", err)
		return
	}
	defer delete(data)

	out: bufio.Writer
	bufio.writer_init(&out, os.to_writer(os.stdout), 64 * 1024)
	defer bufio.writer_destroy(&out)

	simulate(string(data), bufio.writer_to_stream(&out))

	if ferr := bufio.writer_flush(&out); ferr != nil {
		fmt.eprintln("lru: failed to write standard output:", ferr)
	}
}

// simulate executes the program in `input` (capacity line followed by commands) and writes
// each command's output to `w`. Keys and values are slices of `input`, which must outlive the call.
simulate :: proc(input: string, w: io.Writer) {
	rest := input
	first, _ := next_line(&rest)

	capacity, ok := strconv.parse_int(strings.trim_space(first), 10)
	if !ok || capacity < 1 {
		// The spec guarantees a valid capacity; degrade to the smallest legal cache otherwise.
		capacity = 1
	}

	cache: Cache
	cache_init(&cache, capacity)
	defer cache_destroy(&cache)

	for line in next_line(&rest) {
		tokens: [3]string
		n := tokenize(line, tokens[:])

		switch {
		case n == 3 && tokens[0] == "SET":
			cache_set(&cache, tokens[1], tokens[2])
		case n == 2 && tokens[0] == "GET":
			if value, found := cache_get(&cache, tokens[1]); found {
				io.write_string(w, value)
			} else {
				io.write_string(w, "NULL")
			}
			io.write_byte(w, '\n')
		case n == 2 && tokens[0] == "DEL":
			io.write_string(w, "1\n" if cache_del(&cache, tokens[1]) else "0\n")
		case n == 1 && tokens[0] == "SIZE":
			io.write_int(w, cache.count)
			io.write_byte(w, '\n')
		}
		// Blank lines and malformed commands produce no output.
	}
}

// next_line pops the next line from `s`, stripping the `\n` terminator and any trailing `\r`.
// It reports false once `s` is exhausted; a final line without `\n` is still returned.
next_line :: proc(s: ^string) -> (line: string, ok: bool) {
	if len(s^) == 0 {
		return "", false
	}
	if i := strings.index_byte(s^, '\n'); i >= 0 {
		line, s^ = s[:i], s[i + 1:]
	} else {
		line, s^ = s^, ""
	}
	return strings.trim_right(line, "\r"), true
}

// tokenize splits `line` on spaces into `tokens` and returns the number of tokens found.
// Empty tokens are skipped. If the line holds more tokens than fit, len(tokens)+1 is returned
// so that callers can reject it as malformed.
tokenize :: proc(line: string, tokens: []string) -> int {
	n := 0
	rest := line
	for len(rest) > 0 {
		token := rest
		if i := strings.index_byte(rest, ' '); i >= 0 {
			token, rest = rest[:i], rest[i + 1:]
		} else {
			rest = ""
		}
		if len(token) == 0 {
			continue
		}
		if n == len(tokens) {
			return n + 1
		}
		tokens[n] = token
		n += 1
	}
	return n
}

// Node is an entry of the cache's intrusive doubly linked recency list.
// Links are indices into `Cache.nodes`; index SENTINEL is the list head.
Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

SENTINEL :: 0

// Cache is a fixed-capacity LRU cache. Nodes live in a pool and are linked into a circular list
// through the sentinel: `nodes[SENTINEL].next` is the most recently used entry and
// `nodes[SENTINEL].prev` the least recently used. Slots freed by DEL are reused via `free`.
Cache :: struct {
	index:    map[string]i32,
	nodes:    [dynamic]Node,
	free:     [dynamic]i32,
	capacity: int,
	count:    int,
}

cache_init :: proc(c: ^Cache, capacity: int, allocator := context.allocator) {
	// Reserve modestly up front; the pool and map grow on demand so a huge capacity
	// with few commands stays cheap.
	initial := min(capacity, 1 << 16) + 1
	c.capacity = capacity
	c.count = 0
	c.index = make(map[string]i32, initial, allocator)
	c.nodes = make([dynamic]Node, 0, initial, allocator)
	c.free = make([dynamic]i32, allocator)
	append(&c.nodes, Node{prev = SENTINEL, next = SENTINEL})
}

cache_destroy :: proc(c: ^Cache) {
	delete(c.index)
	delete(c.nodes)
	delete(c.free)
	c^ = {}
}

// cache_get returns the value stored under `key` and marks it most recently used.
cache_get :: proc(c: ^Cache, key: string) -> (value: string, found: bool) {
	i := c.index[key] or_return
	move_to_front(c, i)
	return c.nodes[i].value, true
}

// cache_set inserts or overwrites `key`, marks it most recently used, and evicts the least
// recently used entry if the cache would exceed its capacity.
cache_set :: proc(c: ^Cache, key, value: string) {
	if i, found := c.index[key]; found {
		c.nodes[i].value = value
		move_to_front(c, i)
		return
	}

	i: i32
	if c.count == c.capacity {
		// Evict the LRU entry and reuse its slot for the new key.
		i = c.nodes[SENTINEL].prev
		delete_key(&c.index, c.nodes[i].key)
		unlink(c, i)
		c.count -= 1
	} else if len(c.free) > 0 {
		i = pop(&c.free)
	} else {
		i = i32(len(c.nodes))
		append(&c.nodes, Node{})
	}

	c.nodes[i].key = key
	c.nodes[i].value = value
	link_front(c, i)
	c.index[key] = i
	c.count += 1
}

// cache_del removes `key` and reports whether it was present.
cache_del :: proc(c: ^Cache, key: string) -> bool {
	i := c.index[key] or_return
	delete_key(&c.index, key)
	unlink(c, i)
	c.nodes[i] = {}
	append(&c.free, i)
	c.count -= 1
	return true
}

@(private)
unlink :: proc(c: ^Cache, i: i32) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private)
link_front :: proc(c: ^Cache, i: i32) {
	first := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = first
	c.nodes[first].prev = i
	c.nodes[SENTINEL].next = i
}

@(private)
move_to_front :: proc(c: ^Cache, i: i32) {
	if c.nodes[SENTINEL].next == i {
		return
	}
	unlink(c, i)
	link_front(c, i)
}
