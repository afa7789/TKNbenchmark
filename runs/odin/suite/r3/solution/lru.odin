package suite

import "core:bufio"
import "core:strconv"
import "core:strings"

// LRU cache of string keys to string values. Entries live in a node pool linked into a
// circular doubly-linked recency list through a sentinel at index 0: sentinel.next is the
// most recently used entry, sentinel.prev the least. Keys and values borrow the input.
Lru :: struct {
	capacity: int,
	index:    map[string]u32,
	nodes:    [dynamic]Lru_Node,
	free:     [dynamic]u32,
}

Lru_Node :: struct {
	key, value: string,
	prev, next: u32,
}

SENTINEL :: 0

lru_init :: proc(c: ^Lru, capacity: int) {
	c.capacity = capacity
	initial := min(capacity, 1 << 16)
	c.index = make(map[string]u32, initial)
	c.nodes = make([dynamic]Lru_Node, 1, initial + 1)
	c.free = make([dynamic]u32)
}

lru_destroy :: proc(c: ^Lru) {
	delete(c.index)
	delete(c.nodes)
	delete(c.free)
}

lru_len :: proc(c: ^Lru) -> int {
	return len(c.index)
}

@(private = "file")
unlink :: proc(c: ^Lru, i: u32) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private = "file")
push_front :: proc(c: ^Lru, i: u32) {
	first := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = first
	c.nodes[first].prev = i
	c.nodes[SENTINEL].next = i
}

@(private = "file")
release :: proc(c: ^Lru, i: u32) {
	unlink(c, i)
	delete_key(&c.index, c.nodes[i].key)
	c.nodes[i] = {}
	append(&c.free, i)
}

lru_set :: proc(c: ^Lru, key, value: string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		unlink(c, i)
		push_front(c, i)
		return
	}
	if lru_len(c) >= c.capacity {
		release(c, c.nodes[SENTINEL].prev)
	}
	i: u32
	if len(c.free) > 0 {
		i = pop(&c.free)
	} else {
		i = u32(len(c.nodes))
		append(&c.nodes, Lru_Node{})
	}
	c.nodes[i].key = key
	c.nodes[i].value = value
	push_front(c, i)
	c.index[key] = i
}

lru_get :: proc(c: ^Lru, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	unlink(c, i)
	push_front(c, i)
	return c.nodes[i].value, true
}

lru_del :: proc(c: ^Lru, key: string) -> bool {
	i := c.index[key] or_return
	release(c, i)
	return true
}

// lru_run executes the commands in input (capacity on the first line, then one
// command per line) and writes each command's output on its own line.
// Malformed or unknown commands are ignored.
lru_run :: proc(input: string, out: ^bufio.Writer) {
	rest := input
	first, _ := split_line(&rest)
	capacity, ok := strconv.parse_int(strings.trim_space(first), 10)
	if !ok || capacity < 1 {
		return
	}

	cache: Lru
	lru_init(&cache, capacity)
	defer lru_destroy(&cache)

	for line in split_line(&rest) {
		cmd, _, args := strings.partition(line, " ")
		switch cmd {
		case "SET":
			key, _, value := strings.partition(args, " ")
			if key != "" && value != "" {
				lru_set(&cache, key, value)
			}
		case "GET":
			if value, hit := lru_get(&cache, args); hit {
				write_line(out, value)
			} else {
				write_line(out, "NULL")
			}
		case "DEL":
			write_line(out, "1" if lru_del(&cache, args) else "0")
		case "SIZE":
			write_int(out, i64(lru_len(&cache)))
			bufio.writer_write_byte(out, '\n')
		}
	}
}
