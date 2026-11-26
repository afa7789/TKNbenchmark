package main

// entry is a node in the cache's intrusive doubly linked recency list.
// Links are indices into Cache.entries; index 0 is the list sentinel.
type entry struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity least-recently-used cache of string keys and
// values. All operations run in O(1) expected time.
//
// Entries live in a single slice and are linked by index, which keeps
// allocations and GC pressure low for large caches. Slots freed by DEL are
// reused via a free list.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry // entries[0] is the sentinel: next is MRU, prev is LRU
	free     []int32
}

// NewCache returns an empty cache that holds at most capacity keys.
func NewCache(capacity int) *Cache {
	hint := min(capacity+1, 1<<20)
	c := &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		entries:  make([]entry, 1, hint+1),
	}
	return c
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

// Set inserts or overwrites key, marks it most recently used, and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
		c.moveToFront(i)
		return
	}
	if len(c.index) >= c.capacity {
		lru := c.entries[0].prev
		// Reuse the evicted slot directly for the new entry.
		delete(c.index, c.entries[lru].key)
		c.unlink(lru)
		c.entries[lru].key, c.entries[lru].value = key, value
		c.pushFront(lru)
		c.index[key] = lru
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
	delete(c.index, key)
	c.unlink(i)
	c.entries[i] = entry{}
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

func (c *Cache) unlink(i int32) {
	e := &c.entries[i]
	c.entries[e.prev].next = e.next
	c.entries[e.next].prev = e.prev
}

func (c *Cache) pushFront(i int32) {
	head := c.entries[0].next
	c.entries[i].prev, c.entries[i].next = 0, head
	c.entries[head].prev = i
	c.entries[0].next = i
}

func (c *Cache) moveToFront(i int32) {
	if c.entries[0].next == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}
