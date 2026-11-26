package main

import "core:io"
import "core:strconv"
import "core:strings"

NIL_NODE :: -1

@(private = "file")
Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

// LRU cache: a hash map from key to node index plus an intrusive doubly linked
// list over a node pool, most recently used at `head`. All operations are O(1)
// expected. Keys and values borrow from the input buffer.
@(private = "file")
Cache :: struct {
	capacity: int,
	index:    map[string]i32,
	nodes:    [dynamic]Node,
	free:     [dynamic]i32,
	head:     i32,
	tail:     i32,
}

@(private = "file")
cache_init :: proc(c: ^Cache, capacity: int) {
	c.capacity = capacity
	reserve_count := min(capacity + 1, 1 << 16)
	c.index = make(map[string]i32, reserve_count)
	c.nodes = make([dynamic]Node, 0, reserve_count)
	c.free = make([dynamic]i32)
	c.head = NIL_NODE
	c.tail = NIL_NODE
}

@(private = "file")
cache_destroy :: proc(c: ^Cache) {
	delete(c.index)
	delete(c.nodes)
	delete(c.free)
}

@(private = "file")
unlink :: proc(c: ^Cache, i: i32) {
	n := &c.nodes[i]
	if n.prev != NIL_NODE {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != NIL_NODE {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
}

@(private = "file")
push_front :: proc(c: ^Cache, i: i32) {
	n := &c.nodes[i]
	n.prev = NIL_NODE
	n.next = c.head
	if c.head != NIL_NODE {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

@(private = "file")
remove_node :: proc(c: ^Cache, i: i32) {
	unlink(c, i)
	delete_key(&c.index, c.nodes[i].key)
	append(&c.free, i)
}

@(private = "file")
cache_set :: proc(c: ^Cache, key, value: string) {
	if i, found := c.index[key]; found {
		c.nodes[i].value = value
		if c.head != i {
			unlink(c, i)
			push_front(c, i)
		}
		return
	}

	i: i32
	if len(c.free) > 0 {
		i = pop(&c.free)
		c.nodes[i] = {key = key, value = value}
	} else {
		i = i32(len(c.nodes))
		append(&c.nodes, Node{key = key, value = value})
	}
	c.index[key] = i
	push_front(c, i)

	if len(c.index) > c.capacity {
		remove_node(c, c.tail)
	}
}

@(private = "file")
cache_get :: proc(c: ^Cache, key: string) -> (value: string, found: bool) {
	i := c.index[key] or_return
	if c.head != i {
		unlink(c, i)
		push_front(c, i)
	}
	return c.nodes[i].value, true
}

@(private = "file")
cache_del :: proc(c: ^Cache, key: string) -> bool {
	i := c.index[key] or_return
	remove_node(c, i)
	return true
}

// Runs the LRU cache simulation: the first line is the capacity, each later
// line one command.
lru :: proc(input: []byte, w: io.Writer) {
	text := string(input)

	first, _ := strings.split_lines_iterator(&text)
	capacity, ok := strconv.parse_int(strings.trim_space(first), 10)
	if !ok || capacity < 1 {
		return
	}

	cache: Cache
	cache_init(&cache, capacity)
	defer cache_destroy(&cache)

	for line in strings.split_lines_iterator(&text) {
		rest := strings.trim_right(line, "\r")
		cmd, _ := strings.split_iterator(&rest, " ")
		switch cmd {
		case "SET":
			key, _ := strings.split_iterator(&rest, " ")
			value, _ := strings.split_iterator(&rest, " ")
			cache_set(&cache, key, value)
		case "GET":
			key, _ := strings.split_iterator(&rest, " ")
			if value, found := cache_get(&cache, key); found {
				write_line(w, value)
			} else {
				write_line(w, "NULL")
			}
		case "DEL":
			key, _ := strings.split_iterator(&rest, " ")
			write_line(w, "1" if cache_del(&cache, key) else "0")
		case "SIZE":
			write_int(w, i64(len(cache.index)))
			io.write_byte(w, '\n')
		}
	}
}
