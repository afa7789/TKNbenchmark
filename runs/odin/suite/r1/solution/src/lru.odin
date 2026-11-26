package suite

import "core:bufio"
import "core:strconv"
import "core:strings"

NIL_NODE :: -1

// A cache entry. Keys and values are slices of the input buffer, which
// outlives the cache, so no copying is needed.
Lru_Node :: struct {
	key, value: string,
	prev, next: i32,
}

// Fixed-capacity LRU cache: a hash map from key to node index plus an
// intrusive doubly linked list ordered from most (head) to least (tail)
// recently used. Every operation is O(1) expected.
Lru_Cache :: struct {
	capacity: int,
	index:    map[string]i32,
	nodes:    [dynamic]Lru_Node,
	free:     [dynamic]i32,
	head:     i32,
	tail:     i32,
}

lru_init :: proc(c: ^Lru_Cache, capacity: int, allocator := context.allocator) {
	c.capacity = capacity
	c.index = make(map[string]i32, min(capacity, 1 << 16), allocator)
	c.nodes = make([dynamic]Lru_Node, 0, min(capacity, 1 << 16), allocator)
	c.free = make([dynamic]i32, allocator)
	c.head, c.tail = NIL_NODE, NIL_NODE
}

lru_destroy :: proc(c: ^Lru_Cache) {
	delete(c.index)
	delete(c.nodes)
	delete(c.free)
}

lru_size :: proc(c: ^Lru_Cache) -> int {
	return len(c.index)
}

@(private = "file")
unlink :: proc(c: ^Lru_Cache, i: i32) {
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
	n.prev, n.next = NIL_NODE, NIL_NODE
}

@(private = "file")
push_front :: proc(c: ^Lru_Cache, i: i32) {
	n := &c.nodes[i]
	n.prev, n.next = NIL_NODE, c.head
	if c.head != NIL_NODE {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

@(private = "file")
remove_node :: proc(c: ^Lru_Cache, i: i32) {
	unlink(c, i)
	delete_key(&c.index, c.nodes[i].key)
	append(&c.free, i)
}

lru_get :: proc(c: ^Lru_Cache, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	if i != c.head {
		unlink(c, i)
		push_front(c, i)
	}
	return c.nodes[i].value, true
}

lru_set :: proc(c: ^Lru_Cache, key, value: string) {
	if i, found := c.index[key]; found {
		c.nodes[i].value = value
		if i != c.head {
			unlink(c, i)
			push_front(c, i)
		}
		return
	}
	// Evicting before inserting is equivalent to evicting after, since the
	// new key would be the most recently used and never the victim.
	if len(c.index) >= c.capacity {
		remove_node(c, c.tail)
	}
	i: i32
	if len(c.free) > 0 {
		i = pop(&c.free)
		c.nodes[i] = Lru_Node{key = key, value = value}
	} else {
		i = i32(len(c.nodes))
		append(&c.nodes, Lru_Node{key = key, value = value})
	}
	push_front(c, i)
	c.index[key] = i
}

lru_del :: proc(c: ^Lru_Cache, key: string) -> bool {
	i := c.index[key] or_return
	remove_node(c, i)
	return true
}

// Runs the command script in `input`: a capacity line followed by
// SET/GET/DEL/SIZE commands, one per line.
lru :: proc(input: []byte, out: ^bufio.Writer) {
	text := string(input)

	first, _ := strings.split_lines_iterator(&text)
	capacity, ok := strconv.parse_int(strings.trim_space(first), 10)
	if !ok || capacity < 1 {
		return
	}

	cache: Lru_Cache
	lru_init(&cache, capacity)
	defer lru_destroy(&cache)

	for line in strings.split_lines_iterator(&text) {
		rest := strings.trim_right(line, "\r")
		cmd := next_token(&rest)
		switch cmd {
		case "SET":
			key := next_token(&rest)
			value := next_token(&rest)
			lru_set(&cache, key, value)
		case "GET":
			if value, hit := lru_get(&cache, next_token(&rest)); hit {
				write_line(out, value)
			} else {
				write_line(out, "NULL")
			}
		case "DEL":
			write_line(out, "1" if lru_del(&cache, next_token(&rest)) else "0")
		case "SIZE":
			write_int(out, i64(lru_size(&cache)))
			bufio.writer_write_byte(out, '\n')
		}
	}
}

// Splits off the next space-separated token.
@(private = "file")
next_token :: proc(s: ^string) -> string {
	tok, _, rest := strings.partition(s^, " ")
	s^ = rest
	return tok
}
