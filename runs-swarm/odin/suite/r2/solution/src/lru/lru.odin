// Package lru implements `app lru`, which simulates an LRU cache driven by commands read from standard input.
// See the "lru" section of SPEC.md.
package lru

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Node_Index identifies a slot in `Cache.nodes`. Slot `SENTINEL` is the head of the
// circular recency list: `nodes[SENTINEL].next` is the most recently used entry and
// `nodes[SENTINEL].prev` the least recently used one.
Node_Index :: distinct u32

SENTINEL :: Node_Index(0)

Node :: struct {
	key:   string,
	value: string,
	prev:  Node_Index,
	next:  Node_Index,
}

// Cache is an LRU cache whose keys and values are slices borrowed from the input buffer,
// so no per-command allocation happens beyond the map and node pool growth.
Cache :: struct {
	capacity: int,
	index:    map[string]Node_Index,
	nodes:    [dynamic]Node,
	free:     [dynamic]Node_Index,
}

cache_init :: proc(c: ^Cache, capacity: int, expected_keys: int, allocator := context.allocator) {
	reserve := min(capacity, expected_keys) + 1
	c.capacity = capacity
	c.index = make(map[string]Node_Index, reserve, allocator)
	c.nodes = make([dynamic]Node, 1, reserve + 1, allocator)
	c.free = make([dynamic]Node_Index, 0, 0, allocator)
	c.nodes[SENTINEL] = Node{prev = SENTINEL, next = SENTINEL}
}

cache_destroy :: proc(c: ^Cache) {
	delete(c.index)
	delete(c.nodes)
	delete(c.free)
}

@(private)
list_unlink :: #force_inline proc(c: ^Cache, i: Node_Index) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private)
list_push_front :: #force_inline proc(c: ^Cache, i: Node_Index) {
	head := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = head
	c.nodes[head].prev = i
	c.nodes[SENTINEL].next = i
}

@(private)
node_alloc :: proc(c: ^Cache, key, value: string) -> Node_Index {
	node := Node{key = key, value = value}
	if i, ok := pop_safe(&c.free); ok {
		c.nodes[i] = node
		return i
	}
	append(&c.nodes, node)
	return Node_Index(len(c.nodes) - 1)
}

@(private)
node_release :: proc(c: ^Cache, i: Node_Index) {
	list_unlink(c, i)
	delete_key(&c.index, c.nodes[i].key)
	c.nodes[i] = {}
	append(&c.free, i)
}

cache_set :: proc(c: ^Cache, key, value: string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		list_unlink(c, i)
		list_push_front(c, i)
		return
	}

	if len(c.index) >= c.capacity {
		node_release(c, c.nodes[SENTINEL].prev)
	}
	i := node_alloc(c, key, value)
	c.index[key] = i
	list_push_front(c, i)
}

cache_get :: proc(c: ^Cache, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	list_unlink(c, i)
	list_push_front(c, i)
	return c.nodes[i].value, true
}

cache_del :: proc(c: ^Cache, key: string) -> bool {
	i := c.index[key] or_return
	node_release(c, i)
	return true
}

cache_size :: proc(c: ^Cache) -> int {
	return len(c.index)
}

// run is the entry point of the `lru` subcommand.
run :: proc() {
	input, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("app lru: reading standard input:", err)
		os.exit(1)
	}
	defer delete(input)

	out := simulate(string(input))
	defer delete(out)

	if _, werr := os.write(os.stdout, out); werr != nil {
		fmt.eprintln("app lru: writing standard output:", werr)
		os.exit(1)
	}
}

// read_all reads `f` until end of file. Unlike `os.read_entire_file_from_file`, it never trusts the
// size reported by `fstat`, which for pipes on some platforms is only the currently buffered amount.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([]byte, 1 << 20, allocator) or_return
	n := 0
	for {
		if n == len(buf) {
			grown := make([]byte, 2 * len(buf), allocator) or_return
			copy(grown, buf)
			delete(buf, allocator)
			buf = grown
		}
		read, rerr := os.read(f, buf[n:])
		n += read
		if rerr == .EOF || (rerr == nil && read == 0) {
			return buf[:n], nil
		}
		if rerr != nil {
			delete(buf, allocator)
			return nil, rerr
		}
	}
}

// simulate runs the commands in `input` (capacity line first) and returns the produced output.
// Keys and values in the cache borrow from `input`, which must outlive the call.
simulate :: proc(input: string, allocator := context.allocator) -> []byte {
	rest := input
	first, _ := next_line(&rest)
	capacity, cap_ok := strconv.parse_int(strings.trim_space(first), 10)
	if !cap_ok || capacity < 1 {
		return nil
	}

	// Each command line is at least 4 bytes ("SIZE"), which bounds the number of distinct keys.
	expected_keys := len(rest) / 4 + 1

	cache: Cache
	cache_init(&cache, capacity, expected_keys, allocator)
	defer cache_destroy(&cache)

	out := strings.builder_make(0, len(rest) / 2 + 16, allocator)

	for line in next_line(&rest) {
		cmd, args := split_token(line)
		switch cmd {
		case "SET":
			key, value := split_token(args)
			cache_set(&cache, key, value)
		case "GET":
			key, _ := split_token(args)
			if value, ok := cache_get(&cache, key); ok {
				strings.write_string(&out, value)
			} else {
				strings.write_string(&out, "NULL")
			}
			strings.write_byte(&out, '\n')
		case "DEL":
			key, _ := split_token(args)
			strings.write_byte(&out, '1' if cache_del(&cache, key) else '0')
			strings.write_byte(&out, '\n')
		case "SIZE":
			strings.write_int(&out, cache_size(&cache))
			strings.write_byte(&out, '\n')
		}
	}

	return out.buf[:]
}

// next_line pops the next line from `rest`, without its terminator (`\n` or `\r\n`).
@(private)
next_line :: proc(rest: ^string) -> (line: string, ok: bool) {
	if len(rest) == 0 {
		return "", false
	}
	if i := strings.index_byte(rest^, '\n'); i >= 0 {
		line, rest^ = rest[:i], rest[i + 1:]
	} else {
		line, rest^ = rest^, ""
	}
	if len(line) > 0 && line[len(line) - 1] == '\r' {
		line = line[:len(line) - 1]
	}
	return line, true
}

// split_token splits `s` at its first space into the leading token and the remainder.
@(private)
split_token :: #force_inline proc(s: string) -> (token, rest: string) {
	if i := strings.index_byte(s, ' '); i >= 0 {
		return s[:i], s[i + 1:]
	}
	return s, ""
}
