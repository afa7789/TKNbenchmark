package main

// nilIndex marks the absence of a neighbour in the recency list.
const nilIndex = -1

// entry is a node of the intrusive doubly linked recency list.
// Entries live in a slice and refer to each other by index, which keeps
// pointers out of the hot path and lets the garbage collector stay idle.
type entry struct {
	key, value string
	prev, next int
}

// Cache is a fixed-capacity least-recently-used cache.
// All operations run in O(1) expected time.
type Cache struct {
	capacity int
	index    map[string]int
	entries  []entry
	free     []int // indexes of recycled entries
	head     int   // most recently used
	tail     int   // least recently used
}

// NewCache returns an empty cache holding at most capacity keys.
func NewCache(capacity int) *Cache {
	hint := min(capacity+1, 1<<20)
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int, hint),
		entries:  make([]entry, 0, hint),
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
	return c.entries[i].value, true
}

// Set inserts or overwrites key, marks it most recently used and evicts
// the least recently used key if the cache exceeds its capacity.
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

func (c *Cache) alloc(key, value string) int {
	e := entry{key: key, value: value, prev: nilIndex, next: nilIndex}
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		c.entries[i] = e
		return i
	}
	c.entries = append(c.entries, e)
	return len(c.entries) - 1
}

func (c *Cache) remove(i int) {
	c.unlink(i)
	delete(c.index, c.entries[i].key)
	c.entries[i] = entry{prev: nilIndex, next: nilIndex}
	c.free = append(c.free, i)
}

func (c *Cache) moveToFront(i int) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) pushFront(i int) {
	e := &c.entries[i]
	e.prev = nilIndex
	e.next = c.head
	if c.head != nilIndex {
		c.entries[c.head].prev = i
	}
	c.head = i
	if c.tail == nilIndex {
		c.tail = i
	}
}

func (c *Cache) unlink(i int) {
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
