package lru

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"

// Index of the sentinel node in `Cache.nodes`. The list is circular through it:
// sentinel.next is the most recently used entry, sentinel.prev the least.
SENTINEL :: 0

Node :: struct {
	key:   string,
	value: string,
	prev:  u32,
	next:  u32,
}

// LRU cache backed by a hash map from key to node index and an intrusive,
// index-linked doubly linked list. Keys and values are borrowed slices of the
// input buffer, which outlives the cache, so no per-entry copying is needed.
Cache :: struct {
	capacity: int,
	index:    map[string]u32,
	nodes:    [dynamic]Node,
	free:     [dynamic]u32,
}

cache_init :: proc(c: ^Cache, capacity: int, allocator := context.allocator) {
	c.capacity = capacity
	initial := min(capacity, 1 << 16)
	c.index = make(map[string]u32, initial, allocator)
	c.nodes = make([dynamic]Node, 1, initial + 1, allocator)
	c.free = make([dynamic]u32, 0, 0, allocator)
	c.nodes[SENTINEL] = Node{prev = SENTINEL, next = SENTINEL}
}

cache_destroy :: proc(c: ^Cache) {
	delete(c.index)
	delete(c.nodes)
	delete(c.free)
}

cache_size :: proc(c: ^Cache) -> int {
	return len(c.index)
}

@(private = "file")
unlink :: proc(c: ^Cache, i: u32) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private = "file")
push_front :: proc(c: ^Cache, i: u32) {
	head := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = head
	c.nodes[head].prev = i
	c.nodes[SENTINEL].next = i
}

@(private = "file")
alloc_node :: proc(c: ^Cache, key, value: string) -> u32 {
	node := Node{key = key, value = value}
	if i, ok := pop_safe(&c.free); ok {
		c.nodes[i] = node
		return i
	}
	append(&c.nodes, node)
	return u32(len(c.nodes) - 1)
}

cache_set :: proc(c: ^Cache, key, value: string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		unlink(c, i)
		push_front(c, i)
		return
	}

	i := alloc_node(c, key, value)
	c.index[key] = i
	push_front(c, i)

	if len(c.index) > c.capacity {
		lru := c.nodes[SENTINEL].prev
		unlink(c, lru)
		delete_key(&c.index, c.nodes[lru].key)
		append(&c.free, lru)
	}
}

cache_get :: proc(c: ^Cache, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	unlink(c, i)
	push_front(c, i)
	return c.nodes[i].value, true
}

cache_del :: proc(c: ^Cache, key: string) -> bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	delete_key(&c.index, key)
	unlink(c, i)
	c.nodes[i] = {}
	append(&c.free, i)
	return true
}

// Reads all of standard input. Works for pipes, where the size is unknown.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([]byte, 1 << 20, allocator)
	total := 0
	for {
		if total == len(buf) {
			grown := make([]byte, 2 * len(buf), allocator)
			copy(grown, buf)
			delete(buf, allocator)
			buf = grown
		}
		n, rerr := os.read(f, buf[total:])
		total += n
		if rerr == .EOF || (rerr == nil && n == 0) {
			break
		}
		if rerr != nil {
			delete(buf, allocator)
			return nil, rerr
		}
	}
	return buf[:total], nil
}

// Splits `line` at the first space; `rest` is empty if there is none.
split_token :: proc(line: string) -> (head, rest: string) {
	if i := strings.index_byte(line, ' '); i >= 0 {
		return line[:i], line[i + 1:]
	}
	return line, ""
}

main :: proc() {
	input, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("lru: failed to read stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(input)

	text := string(input)

	w: bufio.Writer
	bufio.writer_init(&w, os.to_stream(os.stdout), 1 << 16)
	defer bufio.writer_destroy(&w)
	out := bufio.writer_to_writer(&w)

	cache: Cache
	initialized := false
	defer if initialized do cache_destroy(&cache)

	for raw in strings.split_lines_iterator(&text) {
		line := strings.trim_right(raw, "\r")
		if len(line) == 0 {
			continue
		}

		if !initialized {
			capacity, ok := strconv.parse_int(strings.trim_space(line), 10)
			if !ok || capacity < 1 {
				fmt.eprintln("lru: invalid capacity:", line)
				os.exit(1)
			}
			cache_init(&cache, capacity)
			initialized = true
			continue
		}

		cmd, args := split_token(line)
		switch cmd {
		case "SET":
			key, value := split_token(args)
			cache_set(&cache, key, value)
		case "GET":
			key, _ := split_token(args)
			if value, ok := cache_get(&cache, key); ok {
				io.write_string(out, value)
			} else {
				io.write_string(out, "NULL")
			}
			io.write_byte(out, '\n')
		case "DEL":
			key, _ := split_token(args)
			io.write_string(out, "1\n" if cache_del(&cache, key) else "0\n")
		case "SIZE":
			io.write_int(out, cache_size(&cache))
			io.write_byte(out, '\n')
		}
	}

	bufio.writer_flush(&w)
}
