// lru: simulates an LRU cache driven by commands on standard input.
package main

import "core:bufio"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

NIL :: -1

Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

// LRU cache backed by a pooled, index-linked doubly linked list and a hash map.
// head is the most recently used entry, tail the least recently used.
// Keys and values are slices borrowed from the input buffer, which outlives the cache.
Cache :: struct {
	capacity: int,
	nodes:    [dynamic]Node,
	free:     [dynamic]i32,
	index:    map[string]i32,
	head:     i32,
	tail:     i32,
}

cache_init :: proc(c: ^Cache, capacity: int) {
	c.capacity = capacity
	c.head = NIL
	c.tail = NIL
	// Avoid huge upfront allocations for large capacities; grow on demand.
	reserve_n := min(capacity + 1, 1 << 16)
	c.nodes = make([dynamic]Node, 0, reserve_n)
	c.free = make([dynamic]i32, 0, 64)
	c.index = make(map[string]i32, reserve_n)
}

cache_destroy :: proc(c: ^Cache) {
	delete(c.nodes)
	delete(c.free)
	delete(c.index)
}

@(private = "file")
unlink :: proc(c: ^Cache, i: i32) {
	n := &c.nodes[i]
	if n.prev != NIL {c.nodes[n.prev].next = n.next} else {c.head = n.next}
	if n.next != NIL {c.nodes[n.next].prev = n.prev} else {c.tail = n.prev}
	n.prev, n.next = NIL, NIL
}

@(private = "file")
push_front :: proc(c: ^Cache, i: i32) {
	n := &c.nodes[i]
	n.prev = NIL
	n.next = c.head
	if c.head != NIL {c.nodes[c.head].prev = i} else {c.tail = i}
	c.head = i
}

@(private = "file")
alloc_node :: proc(c: ^Cache, key, value: string) -> i32 {
	node := Node{key = key, value = value, prev = NIL, next = NIL}
	if len(c.free) > 0 {
		i := pop(&c.free)
		c.nodes[i] = node
		return i
	}
	append(&c.nodes, node)
	return i32(len(c.nodes) - 1)
}

@(private = "file")
remove_node :: proc(c: ^Cache, i: i32) {
	unlink(c, i)
	delete_key(&c.index, c.nodes[i].key)
	c.nodes[i] = Node{prev = NIL, next = NIL}
	append(&c.free, i)
}

cache_set :: proc(c: ^Cache, key, value: string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		if c.head != i {
			unlink(c, i)
			push_front(c, i)
		}
		return
	}
	i := alloc_node(c, key, value)
	c.index[key] = i
	push_front(c, i)
	if len(c.index) > c.capacity {
		remove_node(c, c.tail)
	}
}

cache_get :: proc(c: ^Cache, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	if c.head != i {
		unlink(c, i)
		push_front(c, i)
	}
	return c.nodes[i].value, true
}

cache_del :: proc(c: ^Cache, key: string) -> bool {
	i := c.index[key] or_return
	remove_node(c, i)
	return true
}

cache_size :: proc(c: ^Cache) -> int {
	return len(c.index)
}

// Reads f until EOF into a single buffer. The caller owns the returned slice.
read_all :: proc(f: ^os.File) -> (data: []byte, err: os.Error) {
	buf := make([]byte, 1 << 20)
	total := 0
	for {
		if len(buf) - total < 1 << 16 {
			grown := make([]byte, 2 * len(buf))
			copy(grown, buf[:total])
			delete(buf)
			buf = grown
		}
		n, rerr := os.read(f, buf[total:])
		total += n
		if rerr == .EOF || (rerr == nil && n == 0) {
			return buf[:total], nil
		}
		if rerr != nil {
			delete(buf)
			return nil, rerr
		}
	}
}

@(private = "file")
trim_cr :: proc(s: string) -> string {
	return strings.trim_right(s, "\r")
}

run :: proc(input: string, w: io.Writer) {
	rest := input
	first, has_first := strings.split_lines_iterator(&rest)
	if !has_first {
		return
	}
	capacity, ok := strconv.parse_int(strings.trim_space(first), 10)
	if !ok || capacity < 1 {
		capacity = 1
	}

	cache: Cache
	cache_init(&cache, capacity)
	defer cache_destroy(&cache)

	num_buf: [32]byte
	for line_raw in strings.split_lines_iterator(&rest) {
		line := trim_cr(line_raw)
		cmd, _, args := strings.partition(line, " ")
		switch cmd {
		case "SET":
			key, _, value := strings.partition(args, " ")
			cache_set(&cache, key, value)
		case "GET":
			if value, found := cache_get(&cache, args); found {
				io.write_string(w, value)
			} else {
				io.write_string(w, "NULL")
			}
			io.write_byte(w, '\n')
		case "DEL":
			io.write_string(w, "1\n" if cache_del(&cache, args) else "0\n")
		case "SIZE":
			io.write_string(w, strconv.write_int(num_buf[:], i64(cache_size(&cache)), 10))
			io.write_byte(w, '\n')
		}
	}
}

main :: proc() {
	data, err := read_all(os.stdin)
	defer delete(data)
	if err != nil {
		os.write_string(os.stderr, "lru: failed to read standard input\n")
		os.exit(1)
	}

	writer: bufio.Writer
	bufio.writer_init(&writer, os.to_stream(os.stdout), 1 << 16)
	defer bufio.writer_destroy(&writer)

	run(string(data), bufio.writer_to_writer(&writer))
	bufio.writer_flush(&writer)
}
