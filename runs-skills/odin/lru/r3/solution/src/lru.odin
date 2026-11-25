package main

// Sentinel index meaning "no node".
NIL :: -1

Node :: struct {
	key:   string,
	value: string,
	prev:  i32,
	next:  i32,
}

// LRU cache backed by a hash map from key to node index and an intrusive
// doubly-linked list stored in a flat node pool. `head` is the most recently
// used entry, `tail` the least. Freed slots are recycled through `free_head`.
// Keys and values are not copied: callers must keep them alive.
Lru :: struct {
	capacity:  int,
	index:     map[string]i32,
	nodes:     [dynamic]Node,
	head:      i32,
	tail:      i32,
	free_head: i32,
}

lru_init :: proc(c: ^Lru, capacity: int, allocator := context.allocator) {
	c.capacity = capacity
	c.head = NIL
	c.tail = NIL
	c.free_head = NIL
	c.index = make(map[string]i32, allocator)
	c.nodes = make([dynamic]Node, allocator)
	// Pre-size modestly; huge capacities grow on demand.
	initial := min(capacity + 1, 1 << 16)
	reserve(&c.index, initial)
	reserve(&c.nodes, initial)
}

lru_destroy :: proc(c: ^Lru) {
	delete(c.index)
	delete(c.nodes)
	c^ = {}
}

lru_size :: proc(c: ^Lru) -> int {
	return len(c.index)
}

lru_get :: proc(c: ^Lru, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	move_to_front(c, i)
	return c.nodes[i].value, true
}

lru_set :: proc(c: ^Lru, key, value: string) {
	if i, found := c.index[key]; found {
		c.nodes[i].value = value
		move_to_front(c, i)
		return
	}

	i := alloc_node(c)
	c.nodes[i] = Node{key = key, value = value, prev = NIL, next = NIL}
	push_front(c, i)
	c.index[key] = i

	if len(c.index) > c.capacity {
		victim := c.tail
		delete_key(&c.index, c.nodes[victim].key)
		unlink(c, victim)
		free_node(c, victim)
	}
}

lru_del :: proc(c: ^Lru, key: string) -> bool {
	i, found := c.index[key]
	if !found {
		return false
	}
	delete_key(&c.index, key)
	unlink(c, i)
	free_node(c, i)
	return true
}

@(private = "file")
alloc_node :: proc(c: ^Lru) -> i32 {
	if c.free_head != NIL {
		i := c.free_head
		c.free_head = c.nodes[i].next
		return i
	}
	append(&c.nodes, Node{})
	return i32(len(c.nodes) - 1)
}

@(private = "file")
free_node :: proc(c: ^Lru, i: i32) {
	c.nodes[i] = Node{prev = NIL, next = c.free_head}
	c.free_head = i
}

@(private = "file")
unlink :: proc(c: ^Lru, i: i32) {
	n := &c.nodes[i]
	if n.prev != NIL {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != NIL {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
	n.prev = NIL
	n.next = NIL
}

@(private = "file")
push_front :: proc(c: ^Lru, i: i32) {
	n := &c.nodes[i]
	n.prev = NIL
	n.next = c.head
	if c.head != NIL {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

@(private = "file")
move_to_front :: proc(c: ^Lru, i: i32) {
	if c.head == i {
		return
	}
	unlink(c, i)
	push_front(c, i)
}
