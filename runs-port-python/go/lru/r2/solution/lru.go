package main

// Cache is a fixed-capacity least-recently-used cache mapping string keys to
// string values. Every operation runs in O(1) expected time.
//
// Entries live in a slice-backed arena and are linked into a circular doubly
// linked list ordered from most to least recently used. Slot 0 is the list
// sentinel; slots freed by Delete or eviction are recycled through a free list,
// so the arena never grows beyond capacity+1 entries.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32
}

type entry struct {
	key, value string
	prev, next int32
}

const sentinel = 0

// maxPrealloc bounds the up-front allocation so that a huge declared capacity
// does not cost memory until it is actually used.
const maxPrealloc = 1 << 16

// NewCache returns an empty cache that holds at most capacity keys. A
// capacity below one yields a cache that retains nothing.
func NewCache(capacity int) *Cache {
	hint := min(max(capacity, 0), maxPrealloc)
	c := &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		entries:  make([]entry, 1, hint+1),
	}
	return c
}

// Len reports the number of keys currently held.
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

// Set stores value under key, marks it most recently used, and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		c.entries[i].value = string(value)
		c.moveToFront(i)
		return
	}
	k := string(key)
	i := c.alloc(k, string(value))
	c.index[k] = i
	c.pushFront(i)
	if len(c.index) > c.capacity {
		c.remove(c.entries[sentinel].prev)
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

func (c *Cache) alloc(key, value string) int32 {
	e := entry{key: key, value: value}
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		c.entries[i] = e
		return i
	}
	c.entries = append(c.entries, e)
	return int32(len(c.entries) - 1)
}

// remove unlinks entry i, drops it from the index and recycles its slot.
func (c *Cache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.entries[i].key)
	c.entries[i] = entry{}
	c.free = append(c.free, i)
}

func (c *Cache) moveToFront(i int32) {
	if c.entries[sentinel].next == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) unlink(i int32) {
	e := &c.entries[i]
	c.entries[e.prev].next = e.next
	c.entries[e.next].prev = e.prev
}

func (c *Cache) pushFront(i int32) {
	first := c.entries[sentinel].next
	c.entries[i].prev = sentinel
	c.entries[i].next = first
	c.entries[first].prev = i
	c.entries[sentinel].next = i
}
