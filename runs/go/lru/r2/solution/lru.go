package main

// nilIdx marks the absence of a neighbour in the intrusive list.
const nilIdx = -1

// entry is a node of the recency list. Nodes live in a single slice and
// reference each other by index, which keeps allocations and GC pressure low.
type entry struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity LRU cache mapping string keys to string values.
// All operations run in O(1) expected time. It is not safe for concurrent use.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32 // recycled slots in entries
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
		entries:  make([]entry, 0, hint),
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
	e := entry{key: key, value: value, prev: nilIdx, next: nilIdx}
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		c.entries[i] = e
		return i
	}
	c.entries = append(c.entries, e)
	return int32(len(c.entries) - 1)
}

func (c *Cache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.entries[i].key)
	c.entries[i] = entry{} // release strings for GC
	c.free = append(c.free, i)
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
