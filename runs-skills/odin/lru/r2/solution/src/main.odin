package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

// Index of the sentinel node that anchors the circular recency list.
SENTINEL :: 0

Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

// LRU cache with O(1) expected operations. Nodes live in a pool and are
// linked by index; the list runs from most (sentinel.next) to least
// (sentinel.prev) recently used. Keys and values are views into memory
// owned by the caller, which must outlive the cache.
Lru :: struct {
	capacity: int,
	nodes:    [dynamic]Node,
	free:     [dynamic]i32,
	index:    map[string]i32,
}

lru_init :: proc(c: ^Lru, capacity: int, allocator := context.allocator) {
	c.capacity = capacity
	c.nodes = make([dynamic]Node, 1, allocator)
	c.free = make([dynamic]i32, allocator)
	c.index = make(map[string]i32, allocator)
	reserve(&c.nodes, capacity + 1)
	reserve(&c.index, capacity)
}

lru_destroy :: proc(c: ^Lru) {
	delete(c.nodes)
	delete(c.free)
	delete(c.index)
}

lru_size :: proc(c: ^Lru) -> int {
	return len(c.index)
}

@(private = "file")
unlink :: #force_inline proc(c: ^Lru, i: i32) #no_bounds_check {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private = "file")
push_front :: #force_inline proc(c: ^Lru, i: i32) #no_bounds_check {
	head := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = head
	c.nodes[head].prev = i
	c.nodes[SENTINEL].next = i
}

@(private = "file")
release :: proc(c: ^Lru, i: i32) {
	unlink(c, i)
	delete_key(&c.index, c.nodes[i].key)
	c.nodes[i] = {}
	append(&c.free, i)
}

lru_get :: proc(c: ^Lru, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	unlink(c, i)
	push_front(c, i)
	return c.nodes[i].value, true
}

lru_set :: proc(c: ^Lru, key, value: string) {
	if i, found := c.index[key]; found {
		c.nodes[i].value = value
		unlink(c, i)
		push_front(c, i)
		return
	}

	i: i32
	if n, popped := pop_safe(&c.free); popped {
		i = n
	} else {
		i = i32(len(c.nodes))
		append(&c.nodes, Node{})
	}
	c.nodes[i].key = key
	c.nodes[i].value = value
	c.index[key] = i
	push_front(c, i)

	if len(c.index) > c.capacity {
		release(c, c.nodes[SENTINEL].prev)
	}
}

lru_del :: proc(c: ^Lru, key: string) -> bool {
	i := c.index[key] or_return
	release(c, i)
	return true
}

// Buffered stdout writer; flushes when the buffer grows past FLUSH_AT.
FLUSH_AT :: 64 * 1024

Out :: struct {
	buf: [dynamic]byte,
}

out_line :: proc(o: ^Out, s: string) {
	append(&o.buf, s)
	append(&o.buf, '\n')
	if len(o.buf) >= FLUSH_AT {
		out_flush(o)
	}
}

out_int :: proc(o: ^Out, n: int) {
	tmp: [32]byte
	out_line(o, strconv.write_int(tmp[:], i64(n), 10))
}

out_flush :: proc(o: ^Out) {
	if len(o.buf) > 0 {
		_, _ = os.write(os.stdout, o.buf[:])
		clear(&o.buf)
	}
}

// Splits off the next space-separated token from s.
next_token :: proc(s: ^string) -> string {
	tok := s^
	if i := strings.index_byte(tok, ' '); i >= 0 {
		s^ = tok[i + 1:]
		return tok[:i]
	}
	s^ = ""
	return tok
}

// Reads f until EOF. Unlike os.read_entire_file, this does not trust the
// reported file size, which for a pipe is only the bytes currently buffered.
read_all :: proc(f: ^os.File, allocator := context.allocator) -> (data: []byte, err: os.Error) {
	buf := make([dynamic]byte, 0, 1 << 20, allocator) or_return
	for {
		if cap(buf) - len(buf) < 64 * 1024 {
			if rerr := reserve(&buf, 2 * cap(buf)); rerr != nil {
				delete(buf)
				return nil, rerr
			}
		}
		n, rerr := os.read(f, buf[len(buf):cap(buf)])
		non_zero_resize(&buf, len(buf) + n)
		if rerr == .EOF || (rerr == nil && n == 0) {
			return buf[:], nil
		}
		if rerr != nil {
			delete(buf)
			return nil, rerr
		}
	}
}

main :: proc() {
	data, err := read_all(os.stdin)
	if err != nil {
		fmt.eprintln("lru: reading stdin:", os.error_string(err))
		os.exit(1)
	}
	defer delete(data)

	input := string(data)
	first, _ := strings.split_lines_iterator(&input)
	capacity, ok := strconv.parse_int(strings.trim_space(first))
	if !ok || capacity < 1 {
		fmt.eprintln("lru: invalid capacity")
		os.exit(1)
	}

	cache: Lru
	lru_init(&cache, capacity)
	defer lru_destroy(&cache)

	out := Out{buf = make([dynamic]byte, 0, FLUSH_AT + 256)}
	defer delete(out.buf)

	for line in strings.split_lines_iterator(&input) {
		rest := strings.trim_right(line, "\r")
		switch next_token(&rest) {
		case "SET":
			key := next_token(&rest)
			value := next_token(&rest)
			lru_set(&cache, key, value)
		case "GET":
			if value, hit := lru_get(&cache, next_token(&rest)); hit {
				out_line(&out, value)
			} else {
				out_line(&out, "NULL")
			}
		case "DEL":
			out_int(&out, lru_del(&cache, next_token(&rest)) ? 1 : 0)
		case "SIZE":
			out_int(&out, lru_size(&cache))
		}
	}
	out_flush(&out)
}
