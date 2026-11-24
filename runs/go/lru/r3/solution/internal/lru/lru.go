// Package lru implements a fixed-capacity least-recently-used cache of
// string keys and values with O(1) expected-time operations.
package lru

// nilIdx marks the absence of a node link.
const nilIdx = -1

// node is an entry in the recency list. Nodes live in a slice arena and are
// linked by index, which keeps the list compact and avoids per-entry heap
// allocations for the links themselves.
type node struct {
	key, value string
	prev, next int32
}

// Cache is an LRU cache holding at most a fixed number of keys. The zero value
// is not usable; construct one with New. A Cache is not safe for concurrent use.
type Cache struct {
	capacity int
	index    map[string]int32
	nodes    []node
	head     int32 // most recently used
	tail     int32 // least recently used
	free     int32 // head of the free list, chained through node.next
}

// New returns an empty cache that holds at most capacity keys.
// It panics if capacity is less than 1.
func New(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, min(capacity, 1<<16)),
		head:     nilIdx,
		tail:     nilIdx,
		free:     nilIdx,
	}
}

// Len reports the number of keys currently held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored for key and whether it was present.
// A hit marks key as the most recently used.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set stores value under key and marks key as the most recently used. If the
// cache then exceeds its capacity, the least recently used key is evicted.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.moveToFront(i)
		return
	}
	if len(c.index) >= c.capacity {
		c.evict()
	}
	i := c.alloc(key, value)
	c.index[key] = i
	c.pushFront(i)
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key string) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.remove(i)
	return true
}

// evict removes the least recently used entry.
func (c *Cache) evict() {
	if c.tail != nilIdx {
		c.remove(c.tail)
	}
}

// remove unlinks node i, drops it from the index, and recycles its slot.
func (c *Cache) remove(i int32) {
	c.unlink(i)
	n := &c.nodes[i]
	delete(c.index, n.key)
	*n = node{next: c.free, prev: nilIdx}
	c.free = i
}

// alloc returns the index of a node slot initialized with key and value,
// reusing a freed slot when one is available.
func (c *Cache) alloc(key, value string) int32 {
	if c.free != nilIdx {
		i := c.free
		c.free = c.nodes[i].next
		c.nodes[i] = node{key: key, value: value, prev: nilIdx, next: nilIdx}
		return i
	}
	c.nodes = append(c.nodes, node{key: key, value: value, prev: nilIdx, next: nilIdx})
	return int32(len(c.nodes) - 1)
}

func (c *Cache) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) pushFront(i int32) {
	n := &c.nodes[i]
	n.prev = nilIdx
	n.next = c.head
	if c.head != nilIdx {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int32) {
	n := &c.nodes[i]
	if n.prev != nilIdx {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != nilIdx {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
	n.prev, n.next = nilIdx, nilIdx
}
