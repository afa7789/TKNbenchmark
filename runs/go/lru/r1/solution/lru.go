package main

// nilIdx marks the absence of a node in the intrusive linked list.
const nilIdx = -1

// node is an entry in the recency list. Nodes live in a slice and link to
// each other by index, which keeps allocations and GC pressure low.
type node struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity least-recently-used cache of string keys to
// string values. All operations run in O(1) expected time.
type Cache struct {
	capacity int
	index    map[string]int32
	nodes    []node
	free     []int32 // indices of unused slots in nodes
	head     int32   // most recently used
	tail     int32   // least recently used
}

// NewCache returns an empty cache that holds at most capacity keys.
// capacity must be at least 1.
func NewCache(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	hint := min(capacity, 1<<16)
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		nodes:    make([]node, 0, hint),
		head:     nilIdx,
		tail:     nilIdx,
	}
}

// Len reports the number of keys currently held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value for key and marks it most recently used.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set inserts or overwrites key, marks it most recently used, and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.moveToFront(i)
		return
	}
	i := c.alloc(key, value)
	c.index[key] = i
	c.pushFront(i)
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
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

func (c *Cache) alloc(key, value string) int32 {
	n := node{key: key, value: value, prev: nilIdx, next: nilIdx}
	if k := len(c.free); k > 0 {
		i := c.free[k-1]
		c.free = c.free[:k-1]
		c.nodes[i] = n
		return i
	}
	c.nodes = append(c.nodes, n)
	return int32(len(c.nodes) - 1)
}

func (c *Cache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = node{} // drop string references for the GC
	c.free = append(c.free, i)
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

func (c *Cache) pushFront(i int32) {
	n := &c.nodes[i]
	n.prev = nilIdx
	n.next = c.head
	if c.head != nilIdx {
		c.nodes[c.head].prev = i
	}
	c.head = i
	if c.tail == nilIdx {
		c.tail = i
	}
}

func (c *Cache) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}
