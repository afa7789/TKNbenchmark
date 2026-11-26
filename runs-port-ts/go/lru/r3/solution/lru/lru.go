// Package lru implements a fixed-capacity least-recently-used cache with
// O(1) expected-time operations.
package lru

const nilSlot = -1

// entry is a slot in the cache's slab. Recency order is an intrusive doubly
// linked list over slot indices.
type entry struct {
	key, value string
	prev, next int32
}

// Cache is a string-keyed LRU cache. The zero value is not usable; create
// one with New.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32
	head     int32 // most recently used
	tail     int32 // least recently used
}

// maxPrealloc bounds the up-front allocation so that very large capacities
// do not reserve memory that may never be used.
const maxPrealloc = 1 << 16

// New returns an empty cache holding at most capacity keys.
// It panics if capacity is less than 1.
func New(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be positive")
	}
	hint := min(capacity, maxPrealloc)
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		entries:  make([]entry, 0, hint),
		head:     nilSlot,
		tail:     nilSlot,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value for key and marks it most recently used.
func (c *Cache) Get(key string) (string, bool) {
	slot, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(slot)
	return c.entries[slot].value, true
}

// GetBytes is like Get but takes the key as a byte slice, avoiding an
// allocation for the lookup.
func (c *Cache) GetBytes(key []byte) (string, bool) {
	slot, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(slot)
	return c.entries[slot].value, true
}

// Set inserts or overwrites key, marking it most recently used. If the cache
// is full, the least recently used key is evicted first.
func (c *Cache) Set(key, value string) {
	if slot, ok := c.index[key]; ok {
		c.entries[slot].value = value
		c.moveToFront(slot)
		return
	}
	if len(c.index) >= c.capacity {
		c.evictLeastRecent()
	}

	var slot int32
	if n := len(c.free); n > 0 {
		slot = c.free[n-1]
		c.free = c.free[:n-1]
	} else {
		slot = int32(len(c.entries))
		c.entries = append(c.entries, entry{})
	}
	c.entries[slot].key = key
	c.entries[slot].value = value
	c.index[key] = slot
	c.pushFront(slot)
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key string) bool {
	slot, ok := c.index[key]
	if !ok {
		return false
	}
	c.removeSlot(slot)
	return true
}

// DeleteBytes is like Delete but takes the key as a byte slice.
func (c *Cache) DeleteBytes(key []byte) bool {
	slot, ok := c.index[string(key)]
	if !ok {
		return false
	}
	c.removeSlot(slot)
	return true
}

func (c *Cache) evictLeastRecent() {
	if c.tail != nilSlot {
		c.removeSlot(c.tail)
	}
}

func (c *Cache) removeSlot(slot int32) {
	e := &c.entries[slot]
	delete(c.index, e.key)
	c.unlink(slot)
	e.key, e.value = "", ""
	c.free = append(c.free, slot)
}

func (c *Cache) moveToFront(slot int32) {
	if slot == c.head {
		return
	}
	c.unlink(slot)
	c.pushFront(slot)
}

func (c *Cache) pushFront(slot int32) {
	e := &c.entries[slot]
	e.prev = nilSlot
	e.next = c.head
	if c.head != nilSlot {
		c.entries[c.head].prev = slot
	}
	c.head = slot
	if c.tail == nilSlot {
		c.tail = slot
	}
}

func (c *Cache) unlink(slot int32) {
	e := &c.entries[slot]
	p, n := e.prev, e.next
	if p != nilSlot {
		c.entries[p].next = n
	} else {
		c.head = n
	}
	if n != nilSlot {
		c.entries[n].prev = p
	} else {
		c.tail = p
	}
}
