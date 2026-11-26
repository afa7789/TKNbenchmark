package main

// nilIndex marks the absence of a node in the linked list.
const nilIndex = -1

// node is an entry in the cache's recency list. Nodes live in a slice and
// link to each other by index, which keeps them compact and GC-friendly.
type node struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity least-recently-used cache. All operations run in
// O(1) expected time.
type Cache struct {
	capacity int
	index    map[string]int32
	nodes    []node
	free     []int32 // indices of nodes released by Delete
	head     int32   // most recently used
	tail     int32   // least recently used
}

// NewCache returns an empty cache holding at most capacity keys.
// capacity must be at least 1.
func NewCache(capacity int) *Cache {
	hint := min(capacity, 1<<16)
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		nodes:    make([]node, 0, hint),
		head:     nilIndex,
		tail:     nilIndex,
	}
}

// Len reports the number of keys held.
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
	if len(c.index) >= c.capacity {
		// Reuse the evicted node for the new entry.
		i := c.tail
		c.unlink(i)
		delete(c.index, c.nodes[i].key)
		c.nodes[i].key, c.nodes[i].value = key, value
		c.pushFront(i)
		c.index[key] = i
		return
	}
	i := c.alloc(key, value)
	c.pushFront(i)
	c.index[key] = i
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key string) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.unlink(i)
	delete(c.index, key)
	c.nodes[i] = node{} // drop references so the strings can be collected
	c.free = append(c.free, i)
	return true
}

func (c *Cache) alloc(key, value string) int32 {
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		c.nodes[i].key, c.nodes[i].value = key, value
		return i
	}
	c.nodes = append(c.nodes, node{key: key, value: value})
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
	n.prev, n.next = nilIndex, c.head
	if c.head != nilIndex {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int32) {
	n := &c.nodes[i]
	if n.prev != nilIndex {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != nilIndex {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
	n.prev, n.next = nilIndex, nilIndex
}
