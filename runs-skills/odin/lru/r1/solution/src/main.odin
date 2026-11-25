// lru: simulates a least-recently-used cache driven by commands on stdin.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Index of the sentinel node that closes the circular recency list.
SENTINEL :: 0

Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

// Lru keeps entries in a circular doubly linked list (most recent right after
// the sentinel) backed by a node pool, with a hash map from key to node index.
// Keys and values are views into caller-owned memory.
Lru :: struct {
	capacity: int,
	nodes:    [dynamic]Node,
	free:     [dynamic]i32,
	index:    map[string]i32,
}

lru_init :: proc(c: ^Lru, capacity: int, allocator := context.allocator) {
	hint := min(capacity, 1 << 16) + 1
	c.capacity = capacity
	c.nodes = make([dynamic]Node, 0, hint, allocator)
	c.free = make([dynamic]i32, 0, 16, allocator)
	c.index = make(map[string]i32, hint, allocator)
	append(&c.nodes, Node{prev = SENTINEL, next = SENTINEL})
}

lru_destroy :: proc(c: ^Lru) {
	delete(c.nodes)
	delete(c.free)
	delete(c.index)
}

lru_size :: proc(c: ^Lru) -> int {
	return len(c.index)
}

@(private)
unlink :: proc(c: ^Lru, i: i32) #no_bounds_check {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private)
push_front :: proc(c: ^Lru, i: i32) #no_bounds_check {
	first := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = first
	c.nodes[first].prev = i
	c.nodes[SENTINEL].next = i
}

@(private)
alloc_node :: proc(c: ^Lru, key, value: string) -> i32 {
	node := Node{key = key, value = value}
	if i, ok := pop_safe(&c.free); ok {
		c.nodes[i] = node
		return i
	}
	append(&c.nodes, node)
	return i32(len(c.nodes) - 1)
}

lru_set :: proc(c: ^Lru, key, value: string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		unlink(c, i)
		push_front(c, i)
		return
	}

	i: i32
	if len(c.index) >= c.capacity {
		// Evict the least recently used entry and reuse its slot.
		i = c.nodes[SENTINEL].prev
		unlink(c, i)
		delete_key(&c.index, c.nodes[i].key)
		c.nodes[i] = Node{key = key, value = value}
	} else {
		i = alloc_node(c, key, value)
	}
	c.index[key] = i
	push_front(c, i)
}

lru_get :: proc(c: ^Lru, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	unlink(c, i)
	push_front(c, i)
	return c.nodes[i].value, true
}

lru_del :: proc(c: ^Lru, key: string) -> bool {
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

// next_line pops the next line off s, without its terminator (and any '\r').
next_line :: proc(s: ^string) -> (line: string, ok: bool) {
	if len(s) == 0 {
		return "", false
	}
	n := strings.index_byte(s^, '\n')
	if n < 0 {
		line, s^ = s^, ""
	} else {
		line, s^ = s[:n], s[n + 1:]
	}
	return strings.trim_right(line, "\r"), true
}

// split_token returns the text before the first space and the text after it.
split_token :: proc(s: string) -> (head, rest: string) {
	n := strings.index_byte(s, ' ')
	if n < 0 {
		return s, ""
	}
	return s[:n], s[n + 1:]
}

run :: proc(input: string, out: ^strings.Builder) -> bool {
	s := input
	first, has_first := next_line(&s)
	if !has_first {
		return false
	}
	capacity, cap_ok := strconv.parse_int(strings.trim_space(first), 10)
	if !cap_ok || capacity < 1 {
		return false
	}

	cache: Lru
	lru_init(&cache, capacity)
	defer lru_destroy(&cache)

	for line in next_line(&s) {
		cmd, args := split_token(line)
		switch cmd {
		case "SET":
			key, value := split_token(args)
			lru_set(&cache, key, value)
		case "GET":
			key, _ := split_token(args)
			if value, ok := lru_get(&cache, key); ok {
				strings.write_string(out, value)
			} else {
				strings.write_string(out, "NULL")
			}
			strings.write_byte(out, '\n')
		case "DEL":
			key, _ := split_token(args)
			strings.write_byte(out, '1' if lru_del(&cache, key) else '0')
			strings.write_byte(out, '\n')
		case "SIZE":
			strings.write_int(out, lru_size(&cache))
			strings.write_byte(out, '\n')
		}
	}
	return true
}

// read_all reads f until EOF. Unlike os.read_entire_file it does not trust the
// reported file size, which for a pipe is only the currently buffered amount.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, 1 << 20, allocator) or_return
	defer if err != nil {
		delete(buf)
	}
	for {
		if len(buf) == cap(buf) {
			reserve(&buf, 2 * cap(buf)) or_return
		}
		n, rerr := os.read(f, buf[len(buf):cap(buf)])
		non_zero_resize(&buf, len(buf) + n) or_return
		if rerr == .EOF {
			break
		}
		if rerr != nil {
			return nil, rerr
		}
		if n == 0 {
			break
		}
	}
	return buf[:], nil
}

main :: proc() {
	data, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("lru: reading stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(data)

	out := strings.builder_make(0, 1 << 16)
	defer strings.builder_destroy(&out)

	if !run(string(data), &out) {
		fmt.eprintln("lru: invalid capacity line")
		os.exit(1)
	}
	if _, werr := os.write(os.stdout, out.buf[:]); werr != nil {
		fmt.eprintln("lru: writing stdout:", os.error_string(werr))
		os.exit(1)
	}
}
