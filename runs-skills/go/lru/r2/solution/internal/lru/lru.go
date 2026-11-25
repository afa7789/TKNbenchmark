// Package lru implements a fixed-capacity least-recently-used cache.
//
// Entries live in a single slice and are linked by index rather than by
// pointer, which keeps allocations low and the garbage collector idle even
// with millions of entries.
package lru

// nilIdx marks the absence of a neighbouring entry.
const nilIdx = -1

type entry struct {
	key, value string
	prev, next int32
}

// Cache is an LRU cache mapping string keys to string values.
// The zero value is not usable; create one with New.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32 // indices of entries released by Delete
	head     int32   // most recently used
	tail     int32   // least recently used
}

// New returns an empty cache holding at most capacity keys.
// It panics if capacity is less than 1.
func New(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32),
		head:     nilIdx,
		tail:     nilIdx,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored under key and marks it most recently used.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.entries[i].value, true
}

// Set stores value under key and marks it most recently used, evicting the
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
		c.moveToFront(i)
		return
	}
	if len(c.index) >= c.capacity {
		// Reuse the evicted slot directly for the new entry.
		i := c.tail
		c.unlink(i)
		delete(c.index, c.entries[i].key)
		c.entries[i].key, c.entries[i].value = key, value
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
	c.entries[i] = entry{} // release strings for the garbage collector
	c.free = append(c.free, i)
	return true
}

func (c *Cache) alloc(key, value string) int32 {
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		c.entries[i].key, c.entries[i].value = key, value
		return i
	}
	c.entries = append(c.entries, entry{key: key, value: value})
	return int32(len(c.entries) - 1)
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
	e.prev, e.next = nilIdx, c.head
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
