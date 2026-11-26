package main

// nilIndex marks the absence of a neighbour in the recency list.
const nilIndex = -1

// entry is one cached key/value pair, linked into the recency list by index.
type entry struct {
	key, value string
	prev       int32 // towards most recently used
	next       int32 // towards least recently used
}

// Cache is a fixed-capacity LRU cache. Entries live in a pool slice and are
// linked into a doubly linked recency list by index; a map indexes them by key.
// Every operation runs in O(1) expected time.
type Cache struct {
	capacity int
	entries  []entry
	index    map[string]int32
	head     int32 // most recently used, or nilIndex
	tail     int32 // least recently used, or nilIndex
	free     int32 // head of the free-entry stack (linked via next), or nilIndex
}

// NewCache returns an empty cache holding at most capacity keys (minimum 1).
func NewCache(capacity int) *Cache {
	capacity = max(capacity, 1)
	hint := min(capacity, 1<<20)
	return &Cache{
		capacity: capacity,
		entries:  make([]entry, 0, hint),
		index:    make(map[string]int32, hint),
		head:     nilIndex,
		tail:     nilIndex,
		free:     nilIndex,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Set inserts or overwrites key, making it the most recently used. If the
// cache would exceed its capacity, the least recently used key is evicted.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
		c.touch(i)
		return
	}
	if len(c.index) == c.capacity {
		c.remove(c.tail)
	}
	i := c.alloc()
	c.entries[i] = entry{key: key, value: value}
	c.index[key] = i
	c.pushFront(i)
}

// Get returns the value for key and whether it was present. A hit makes the
// key the most recently used.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.touch(i)
	return c.entries[i].value, true
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

func (c *Cache) alloc() int32 {
	if c.free != nilIndex {
		i := c.free
		c.free = c.entries[i].next
		return i
	}
	c.entries = append(c.entries, entry{})
	return int32(len(c.entries) - 1)
}

// remove unlinks entry i, drops it from the index and recycles its slot.
func (c *Cache) remove(i int32) {
	e := &c.entries[i]
	delete(c.index, e.key)
	c.unlink(i)
	*e = entry{next: c.free} // release the strings
	c.free = i
}

func (c *Cache) touch(i int32) {
	if c.head != i {
		c.unlink(i)
		c.pushFront(i)
	}
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
