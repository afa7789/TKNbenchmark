package main

// nilIndex marks the absence of a neighbouring entry in the recency list.
const nilIndex = -1

type entry struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity LRU cache. Entries live in a slice and are linked
// by index into a doubly-linked recency list, which keeps every operation O(1)
// while avoiding a heap allocation per entry.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32 // slots in entries released by Delete
	head     int32   // most recently used
	tail     int32   // least recently used
}

// NewCache returns an empty cache that holds at most capacity keys.
func NewCache(capacity int) *Cache {
	if capacity < 1 {
		capacity = 1
	}
	hint := min(capacity, 1<<16)
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		entries:  make([]entry, 0, hint),
		head:     nilIndex,
		tail:     nilIndex,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored under key and marks it most recently used.
func (c *Cache) Get(key []byte) (string, bool) {
	i, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.entries[i].value, true
}

// Set inserts or overwrites key, marks it most recently used, and evicts the
// least recently used key if the cache is over capacity.
func (c *Cache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		c.entries[i].value = string(value)
		c.moveToFront(i)
		return
	}
	k := string(key)
	i := c.alloc(entry{key: k, value: string(value)})
	c.index[k] = i
	c.pushFront(i)
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key []byte) bool {
	i, ok := c.index[string(key)]
	if !ok {
		return false
	}
	c.remove(i)
	return true
}

func (c *Cache) alloc(e entry) int32 {
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
	c.entries[i] = entry{} // release strings to the garbage collector
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
	e.prev = nilIndex
	e.next = c.head
	if c.head != nilIndex {
		c.entries[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int32) {
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
