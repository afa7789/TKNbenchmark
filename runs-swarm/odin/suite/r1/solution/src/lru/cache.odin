package lru

// An LRU cache of string keys to string values.
//
// Entries live in a pool of nodes linked into a doubly-linked recency list by
// index; slot 0 is a sentinel whose `next` is the most recently used entry and
// whose `prev` is the least recently used one. A map from key to node index
// gives O(1) expected lookup. Evicted and deleted slots are recycled through a
// free list, so the pool never grows beyond the largest number of keys held
// at once (plus the sentinel).
//
// Keys and values are not copied: the caller must keep the memory they point
// into alive for as long as the cache is in use.

@(private)
Node_Index :: distinct u32

@(private)
SENTINEL :: Node_Index(0)

@(private)
Node :: struct {
	key:   string,
	value: string,
	prev:  Node_Index,
	next:  Node_Index,
}

@(private)
Cache :: struct {
	capacity: int,
	nodes:    [dynamic]Node,
	index:    map[string]Node_Index,
	// Head of the free list of recycled slots, chained through `next`;
	// SENTINEL when empty.
	free:     Node_Index,
}

// `expected_keys` is a hint used to pre-size the storage.
@(private)
cache_init :: proc(c: ^Cache, capacity: int, expected_keys: int, allocator := context.allocator) {
	assert(capacity >= 1)
	reserve_keys := clamp(expected_keys, 0, capacity)

	c.capacity = capacity
	c.nodes = make([dynamic]Node, 1, reserve_keys + 1, allocator)
	c.index = make(map[string]Node_Index, reserve_keys, allocator)
	c.free = SENTINEL
	c.nodes[SENTINEL].prev = SENTINEL
	c.nodes[SENTINEL].next = SENTINEL
}

@(private)
cache_destroy :: proc(c: ^Cache) {
	delete(c.nodes)
	delete(c.index)
	c^ = {}
}

@(private)
cache_len :: proc(c: ^Cache) -> int {
	return len(c.index)
}

// Inserts or overwrites `key`, making it the most recently used entry, and
// evicts the least recently used entry if the cache is over capacity.
@(private)
cache_set :: proc(c: ^Cache, key, value: string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		move_to_front(c, i)
		return
	}

	if len(c.index) >= c.capacity {
		evict_lru(c)
	}

	i := alloc_node(c)
	c.nodes[i].key = key
	c.nodes[i].value = value
	link_front(c, i)
	c.index[key] = i
}

// Looks up `key`; a hit makes it the most recently used entry.
@(private)
cache_get :: proc(c: ^Cache, key: string) -> (value: string, ok: bool) {
	i := c.index[key] or_return
	move_to_front(c, i)
	return c.nodes[i].value, true
}

// Removes `key`, reporting whether it was present.
@(private)
cache_del :: proc(c: ^Cache, key: string) -> (was_present: bool) {
	_, i := delete_key(&c.index, key)
	if i == SENTINEL {
		return false
	}
	unlink(c, i)
	free_node(c, i)
	return true
}

@(private = "file")
evict_lru :: proc(c: ^Cache) {
	lru := c.nodes[SENTINEL].prev
	assert(lru != SENTINEL)
	delete_key(&c.index, c.nodes[lru].key)
	unlink(c, lru)
	free_node(c, lru)
}

@(private = "file")
alloc_node :: proc(c: ^Cache) -> Node_Index {
	if c.free != SENTINEL {
		i := c.free
		c.free = c.nodes[i].next
		return i
	}
	append(&c.nodes, Node{})
	return Node_Index(len(c.nodes) - 1)
}

@(private = "file")
free_node :: proc(c: ^Cache, i: Node_Index) {
	c.nodes[i] = Node {
		next = c.free,
	}
	c.free = i
}

@(private = "file")
unlink :: proc(c: ^Cache, i: Node_Index) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

@(private = "file")
link_front :: proc(c: ^Cache, i: Node_Index) {
	first := c.nodes[SENTINEL].next
	c.nodes[i].prev = SENTINEL
	c.nodes[i].next = first
	c.nodes[first].prev = i
	c.nodes[SENTINEL].next = i
}

@(private = "file")
move_to_front :: proc(c: ^Cache, i: Node_Index) {
	if c.nodes[SENTINEL].next == i {
		return
	}
	unlink(c, i)
	link_front(c, i)
}
