// lru: simulates a least-recently-used cache driven by commands on stdin.
package main

import "core:bufio"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

NIL :: 0 // Index of the sentinel node in the recency list.

Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

// Cache is an LRU cache backed by a hash map from key to node index and an
// intrusive circular doubly-linked list stored in a node pool. Node 0 is the
// sentinel: sentinel.next is the most recently used entry, sentinel.prev the
// least recently used. Unused nodes are chained through `next` in a free list.
// Keys and values are borrowed slices; their storage must outlive the cache.
Cache :: struct {
	capacity:  int,
	nodes:     [dynamic]Node,
	index:     map[string]i32,
	free_head: i32,
}

cache_init :: proc(c: ^Cache, capacity: int, size_hint: int) {
	hint := min(capacity, size_hint) + 1
	c.capacity = capacity
	c.nodes = make([dynamic]Node, 1, hint + 1)
	c.index = make(map[string]i32, hint)
	c.free_head = NIL
}

cache_destroy :: proc(c: ^Cache) {
	delete(c.nodes)
	delete(c.index)
}

cache_size :: #force_inline proc(c: ^Cache) -> int {
	return len(c.index)
}

@(private = "file")
unlink :: #force_inline proc(c: ^Cache, i: i32) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private = "file")
push_front :: #force_inline proc(c: ^Cache, i: i32) {
	head := c.nodes[NIL].next
	c.nodes[i].prev = NIL
	c.nodes[i].next = head
	c.nodes[head].prev = i
	c.nodes[NIL].next = i
}

@(private = "file")
alloc_node :: proc(c: ^Cache) -> i32 {
	if c.free_head != NIL {
		i := c.free_head
		c.free_head = c.nodes[i].next
		return i
	}
	append(&c.nodes, Node{})
	return i32(len(c.nodes) - 1)
}

@(private = "file")
release_node :: proc(c: ^Cache, i: i32) {
	c.nodes[i] = Node{next = c.free_head}
	c.free_head = i
}

cache_get :: proc(c: ^Cache, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	unlink(c, i)
	push_front(c, i)
	return c.nodes[i].value, true
}

cache_set :: proc(c: ^Cache, key, value: string) {
	if i, found := c.index[key]; found {
		c.nodes[i].value = value
		unlink(c, i)
		push_front(c, i)
		return
	}

	i := alloc_node(c)
	c.nodes[i].key = key
	c.nodes[i].value = value
	push_front(c, i)
	c.index[key] = i

	if len(c.index) > c.capacity {
		lru := c.nodes[NIL].prev
		unlink(c, lru)
		delete_key(&c.index, c.nodes[lru].key)
		release_node(c, lru)
	}
}

cache_del :: proc(c: ^Cache, key: string) -> bool {
	i, found := c.index[key]
	if !found {
		return false
	}
	delete_key(&c.index, key)
	unlink(c, i)
	release_node(c, i)
	return true
}

read_all :: proc(f: ^os.File) -> []byte {
	CHUNK :: 1 << 16
	buf := make([dynamic]byte, CHUNK)
	total := 0
	for {
		if len(buf) - total < CHUNK {
			resize(&buf, 2 * len(buf))
		}
		n, err := os.read(f, buf[total:])
		total += n
		if err != nil || n == 0 {
			break
		}
	}
	return buf[:total]
}

// next_token splits off the next space-separated token from `s`.
next_token :: #force_inline proc(s: ^string) -> string {
	rest := s^
	if i := strings.index_byte(rest, ' '); i >= 0 {
		s^ = rest[i + 1:]
		return rest[:i]
	}
	s^ = ""
	return rest
}

main :: proc() {
	data := read_all(os.stdin)
	defer delete(data)
	input := string(data)

	writer: bufio.Writer
	bufio.writer_init(&writer, os.to_stream(os.stdout), 1 << 16)
	defer bufio.writer_destroy(&writer)
	w := bufio.writer_to_writer(&writer)

	cache: Cache
	cache_initialized := false
	defer if cache_initialized do cache_destroy(&cache)

	for raw_line in strings.split_lines_iterator(&input) {
		line := strings.trim_right(raw_line, "\r")
		if len(line) == 0 {
			continue
		}

		if !cache_initialized {
			capacity, ok := strconv.parse_int(strings.trim_space(line), 10)
			if !ok || capacity < 1 {
				capacity = 1
			}
			// Each command is at least ~5 bytes; bound preallocation by input size.
			cache_init(&cache, capacity, len(input) / 8)
			cache_initialized = true
			continue
		}

		rest := line
		switch next_token(&rest) {
		case "SET":
			key := next_token(&rest)
			value := next_token(&rest)
			cache_set(&cache, key, value)
		case "GET":
			if value, ok := cache_get(&cache, next_token(&rest)); ok {
				io.write_string(w, value)
			} else {
				io.write_string(w, "NULL")
			}
			io.write_byte(w, '\n')
		case "DEL":
			io.write_string(w, "1\n" if cache_del(&cache, next_token(&rest)) else "0\n")
		case "SIZE":
			io.write_int(w, cache_size(&cache))
			io.write_byte(w, '\n')
		}
	}

	bufio.writer_flush(&writer)
}
