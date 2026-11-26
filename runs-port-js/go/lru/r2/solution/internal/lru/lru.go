// Package lru implements a fixed-capacity least-recently-used cache.
package lru

// sentinel is the index of the list head node. next[sentinel] is the most
// recently used entry and prev[sentinel] the least recently used one.
const sentinel = 0

type node[V any] struct {
	key        string
	value      V
	prev, next int32
}

// Cache is a fixed-capacity LRU cache keyed by strings. It is backed by a hash
// map and an intrusive doubly linked list stored in a slice, so every
// operation runs in O(1) expected time. A Cache is not safe for concurrent use.
type Cache[V any] struct {
	capacity int
	index    map[string]int32
	nodes    []node[V] // nodes[0] is the sentinel
	free     []int32   // indices of released nodes available for reuse
}

// New returns an empty cache that holds at most capacity entries.
// It panics if capacity is less than 1.
func New[V any](capacity int) *Cache[V] {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	// Grow storage on demand so a large capacity with few keys stays cheap.
	hint := min(capacity, 1<<16)
	c := &Cache[V]{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		nodes:    make([]node[V], 1, hint+1),
	}
	return c
}

// Len reports the number of entries held.
func (c *Cache[V]) Len() int { return len(c.index) }

// Get returns the value stored for key and marks it most recently used.
// The boolean reports whether the key was present.
func (c *Cache[V]) Get(key string) (V, bool) {
	i, ok := c.index[key]
	if !ok {
		var zero V
		return zero, false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set inserts or overwrites key and marks it most recently used, evicting the
// least recently used entry if the cache would exceed its capacity.
func (c *Cache[V]) Set(key string, value V) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.moveToFront(i)
		return
	}
	if len(c.index) == c.capacity {
		c.remove(c.nodes[sentinel].prev)
	}
	i := c.alloc()
	c.nodes[i].key = key
	c.nodes[i].value = value
	c.index[key] = i
	c.pushFront(i)
}

// Delete removes key and reports whether it was present.
func (c *Cache[V]) Delete(key string) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.remove(i)
	return true
}

func (c *Cache[V]) alloc() int32 {
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		return i
	}
	c.nodes = append(c.nodes, node[V]{})
	return int32(len(c.nodes) - 1)
}

func (c *Cache[V]) remove(i int32) {
	delete(c.index, c.nodes[i].key)
	c.unlink(i)
	c.nodes[i] = node[V]{} // drop references so they can be collected
	c.free = append(c.free, i)
}

func (c *Cache[V]) moveToFront(i int32) {
	if c.nodes[sentinel].next == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache[V]) unlink(i int32) {
	p, n := c.nodes[i].prev, c.nodes[i].next
	c.nodes[p].next = n
	c.nodes[n].prev = p
}

func (c *Cache[V]) pushFront(i int32) {
	first := c.nodes[sentinel].next
	c.nodes[i].prev = sentinel
	c.nodes[i].next = first
	c.nodes[first].prev = i
	c.nodes[sentinel].next = i
}
