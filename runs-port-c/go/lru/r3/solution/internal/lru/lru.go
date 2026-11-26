// Package lru implements a fixed-capacity least-recently-used cache with
// O(1) expected time for every operation.
package lru

// nilIndex marks the absence of a node in the recency list or free list.
const nilIndex = -1

type node struct {
	key, value string
	prev, next int32 // towards more / less recently used
}

// Cache is an LRU cache mapping string keys to string values. Entries live in
// a node pool linked into an intrusive doubly linked recency list, so the
// steady state performs no per-entry allocation beyond the map itself.
//
// The zero value is not usable; create caches with New.
type Cache struct {
	index    map[string]int32
	nodes    []node
	free     int32 // head of the free list, chained through node.next
	head     int32 // most recently used
	tail     int32 // least recently used
	capacity int
}

// New returns an empty cache holding at most capacity keys. sizeHint is the
// expected peak number of entries and is used only to preallocate storage.
// New panics if capacity is less than 1.
func New(capacity, sizeHint int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	sizeHint = max(0, min(sizeHint, capacity))
	return &Cache{
		index:    make(map[string]int32, sizeHint),
		nodes:    make([]node, 0, sizeHint),
		free:     nilIndex,
		head:     nilIndex,
		tail:     nilIndex,
		capacity: capacity,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored for key and marks key as the most recently
// used. The boolean reports whether the key was present.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.touch(i)
	return c.nodes[i].value, true
}

// Set inserts or overwrites key and marks it as the most recently used. If
// the cache then holds more than its capacity, the least recently used key
// is evicted.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.touch(i)
		return
	}
	if len(c.index) == c.capacity {
		c.remove(c.tail)
	}
	i := c.alloc()
	c.nodes[i] = node{key: key, value: value}
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

func (c *Cache) alloc() int32 {
	if i := c.free; i != nilIndex {
		c.free = c.nodes[i].next
		return i
	}
	c.nodes = append(c.nodes, node{})
	return int32(len(c.nodes) - 1)
}

// remove unlinks node i, drops it from the index and recycles its slot.
func (c *Cache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = node{next: c.free} // release strings for the GC
	c.free = i
}

func (c *Cache) touch(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
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
}

func (c *Cache) pushFront(i int32) {
	n := &c.nodes[i]
	n.prev = nilIndex
	n.next = c.head
	if c.head != nilIndex {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}
