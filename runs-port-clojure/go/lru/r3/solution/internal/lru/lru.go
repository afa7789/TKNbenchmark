// Package lru implements a fixed-capacity least-recently-used cache with
// O(1) expected-time operations.
package lru

// nilIndex marks the absence of a neighbour in the intrusive list.
const nilIndex = -1

type entry[K comparable, V any] struct {
	key        K
	value      V
	prev, next int32
}

// Cache is an LRU cache holding at most a fixed number of keys. Entries live
// in a slice and are linked by index, which keeps allocations low and lets
// freed slots be reused. The zero value is not usable; call New.
type Cache[K comparable, V any] struct {
	capacity int
	index    map[K]int32
	entries  []entry[K, V]
	free     []int32
	head     int32 // most recently used
	tail     int32 // least recently used
}

// New returns an empty cache that holds at most capacity keys. A capacity
// below one yields a cache that never retains anything.
func New[K comparable, V any](capacity int) *Cache[K, V] {
	hint := min(max(capacity, 0)+1, 1<<20)
	return &Cache[K, V]{
		capacity: capacity,
		index:    make(map[K]int32, hint),
		entries:  make([]entry[K, V], 0, hint),
		head:     nilIndex,
		tail:     nilIndex,
	}
}

// Len reports the number of keys currently held.
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

// Set inserts or overwrites key, marks it most recently used, and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *Cache[K, V]) Set(key K, value V) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
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
func (c *Cache[K, V]) Delete(key K) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.remove(i)
	return true
}

func (c *Cache[K, V]) alloc(key K, value V) int32 {
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		c.entries[i] = entry[K, V]{key: key, value: value}
		return i
	}
	c.entries = append(c.entries, entry[K, V]{key: key, value: value})
	return int32(len(c.entries) - 1)
}

func (c *Cache[K, V]) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.entries[i].key)
	c.entries[i] = entry[K, V]{} // release references for the GC
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
	e := &c.entries[i]
	e.prev = nilIndex
	e.next = c.head
	if c.head != nilIndex {
		c.entries[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache[K, V]) unlink(i int32) {
	e := &c.entries[i]
	if e.prev != nilIndex {
		c.entries[e.prev].next = e.next
	} else {
		c.head = e.next
	}
	if e.next != nilIndex {
		c.entries[e.next].prev = e.prev
	} else {
		c.tail = e.prev
	}
	e.prev, e.next = nilIndex, nilIndex
}
