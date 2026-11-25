// Package lru implements a fixed-capacity least-recently-used cache.
//
// Entries live in a slice-backed doubly linked list addressed by index, which
// keeps every operation O(1) expected time and avoids a heap allocation per entry.
package lru

// nilIdx marks the absence of a neighbour in the recency list.
const nilIdx = -1

type entry[K comparable, V any] struct {
	key        K
	value      V
	prev, next int32
}

// Cache is an LRU cache holding at most a fixed number of entries.
// The zero value is not usable; create one with New. A Cache is not safe for
// concurrent use.
type Cache[K comparable, V any] struct {
	capacity int
	index    map[K]int32
	entries  []entry[K, V]
	free     []int32 // slots in entries released by Delete
	head     int32   // most recently used
	tail     int32   // least recently used
}

// New returns an empty cache that holds at most capacity entries.
// It panics if capacity is not positive.
func New[K comparable, V any](capacity int) *Cache[K, V] {
	if capacity <= 0 {
		panic("lru: capacity must be positive")
	}
	return &Cache[K, V]{
		capacity: capacity,
		index:    make(map[K]int32),
		head:     nilIdx,
		tail:     nilIdx,
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
	return c.entries[i].value, true
}

// Set stores value for key and marks it most recently used. If the cache then
// exceeds its capacity, the least recently used entry is evicted.
func (c *Cache[K, V]) Set(key K, value V) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
		c.moveToFront(i)
		return
	}

	var i int32
	switch {
	case len(c.index) >= c.capacity:
		// Reuse the evicted tail's slot for the new entry.
		i = c.tail
		c.unlink(i)
		delete(c.index, c.entries[i].key)
	case len(c.free) > 0:
		i = c.free[len(c.free)-1]
		c.free = c.free[:len(c.free)-1]
	default:
		c.entries = append(c.entries, entry[K, V]{})
		i = int32(len(c.entries) - 1)
	}

	c.entries[i] = entry[K, V]{key: key, value: value, prev: nilIdx, next: nilIdx}
	c.index[key] = i
	c.pushFront(i)
}

// Delete removes key from the cache and reports whether it was present.
func (c *Cache[K, V]) Delete(key K) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.unlink(i)
	delete(c.index, key)
	c.entries[i] = entry[K, V]{} // drop references so they can be collected
	c.free = append(c.free, i)
	return true
}

func (c *Cache[K, V]) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache[K, V]) pushFront(i int32) {
	e := &c.entries[i]
	e.prev = nilIdx
	e.next = c.head
	if c.head != nilIdx {
		c.entries[c.head].prev = i
	}
	c.head = i
	if c.tail == nilIdx {
		c.tail = i
	}
}

func (c *Cache[K, V]) unlink(i int32) {
	e := &c.entries[i]
	if e.prev != nilIdx {
		c.entries[e.prev].next = e.next
	} else {
		c.head = e.next
	}
	if e.next != nilIdx {
		c.entries[e.next].prev = e.prev
	} else {
		c.tail = e.prev
	}
	e.prev, e.next = nilIdx, nilIdx
}
