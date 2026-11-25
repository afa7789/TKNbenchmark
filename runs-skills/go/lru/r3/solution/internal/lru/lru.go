// Package lru implements a fixed-capacity least-recently-used cache with O(1)
// expected-time operations.
package lru

// nilIdx marks the absence of a neighbour in the intrusive linked list.
const nilIdx = -1

type entry struct {
	key, value string
	prev, next int32
}

// Cache is a string-keyed LRU cache. Entries live in a single slice and are
// linked by index, which keeps allocations and GC pressure low. The zero value
// is not usable; construct with New. Cache is not safe for concurrent use.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32 // slots released by Delete, available for reuse
	head     int32   // most recently used
	tail     int32   // least recently used
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
	}
}

// Len reports the number of keys currently held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored for key and marks it most recently used.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.entries[i].value, true
}

// Set inserts or overwrites key, marks it most recently used, and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
		c.moveToFront(i)
		return
	}
	var i int32
	switch {
	case len(c.index) >= c.capacity:
		// Reuse the evicted slot directly.
		i = c.tail
		c.unlink(i)
		delete(c.index, c.entries[i].key)
	case len(c.free) > 0:
		i = c.free[len(c.free)-1]
		c.free = c.free[:len(c.free)-1]
	default:
		i = int32(len(c.entries))
		c.entries = append(c.entries, entry{})
	}
	c.entries[i] = entry{key: key, value: value, prev: nilIdx, next: nilIdx}
	c.index[key] = i
	c.pushFront(i)
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key string) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.unlink(i)
	delete(c.index, key)
	c.entries[i] = entry{} // drop string references for the GC
	c.free = append(c.free, i)
	return true
}

func (c *Cache) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) pushFront(i int32) {
	e := &c.entries[i]
	e.prev = nilIdx
	e.next = c.head
	if c.head != nilIdx {
		c.entries[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int32) {
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
