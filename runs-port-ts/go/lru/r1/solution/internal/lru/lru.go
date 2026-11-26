// Package lru implements a fixed-capacity least-recently-used cache.
package lru

// nilIndex marks the absence of a neighbouring node.
const nilIndex = -1

type node[K comparable, V any] struct {
	key        K
	value      V
	prev, next int32
}

// Cache is a fixed-capacity LRU cache. Entries live in a slab of nodes linked
// into a doubly linked list ordered from most to least recently used, so every
// operation runs in O(1) expected time without per-entry heap allocations.
//
// A Cache is not safe for concurrent use.
type Cache[K comparable, V any] struct {
	capacity int
	index    map[K]int32
	nodes    []node[K, V]
	free     []int32
	head     int32 // most recently used
	tail     int32 // least recently used
}

// New returns an empty cache holding at most capacity entries.
// It panics if capacity is not positive.
func New[K comparable, V any](capacity int) *Cache[K, V] {
	if capacity < 1 {
		panic("lru: capacity must be positive")
	}
	return &Cache[K, V]{
		capacity: capacity,
		index:    make(map[K]int32),
		head:     nilIndex,
		tail:     nilIndex,
	}
}

// Len reports the number of entries in the cache.
func (c *Cache[K, V]) Len() int { return len(c.index) }

// Get returns the value stored for key and marks it most recently used.
func (c *Cache[K, V]) Get(key K) (V, bool) {
	i, ok := c.index[key]
	if !ok {
		var zero V
		return zero, false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set inserts or overwrites key, marks it most recently used and evicts the
// least recently used entry if the cache exceeds its capacity.
func (c *Cache[K, V]) Set(key K, value V) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.moveToFront(i)
		return
	}
	if len(c.index) >= c.capacity {
		c.remove(c.tail)
	}
	i := c.alloc(key, value)
	c.index[key] = i
	c.pushFront(i)
}

// Delete removes key and reports whether it was present.
func (c *Cache[K, V]) Delete(key K) bool {
	i, ok := c.index[key]
	if ok {
		c.remove(i)
	}
	return ok
}

func (c *Cache[K, V]) alloc(key K, value V) int32 {
	n := node[K, V]{key: key, value: value, prev: nilIndex, next: nilIndex}
	if last := len(c.free) - 1; last >= 0 {
		i := c.free[last]
		c.free = c.free[:last]
		c.nodes[i] = n
		return i
	}
	c.nodes = append(c.nodes, n)
	return int32(len(c.nodes) - 1)
}

func (c *Cache[K, V]) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = node[K, V]{} // release references for the garbage collector
	c.free = append(c.free, i)
}

func (c *Cache[K, V]) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache[K, V]) pushFront(i int32) {
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

func (c *Cache[K, V]) unlink(i int32) {
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
