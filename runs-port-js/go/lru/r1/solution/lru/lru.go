// Package lru implements a fixed-capacity least-recently-used cache.
package lru

const nilSlot = -1

type entry struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity LRU cache mapping string keys to string values.
// Entries live in a slice and form an intrusive doubly linked list ordered
// from most to least recently used; every operation is O(1) expected.
// The zero value is not usable; construct one with New.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32
	head     int32 // most recently used
	tail     int32 // least recently used
}

// New returns an empty cache that holds at most capacity keys.
// It panics if capacity is not positive.
func New(capacity int) *Cache {
	if capacity <= 0 {
		panic("lru: capacity must be positive")
	}
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32),
		head:     nilSlot,
		tail:     nilSlot,
	}
}

// Len reports the number of keys currently held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored for key and marks it most recently used.
func (c *Cache) Get(key string) (string, bool) {
	slot, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(slot)
	return c.entries[slot].value, true
}

// Set inserts or overwrites key, marks it most recently used, and evicts the
// least recently used key if the cache would exceed its capacity.
func (c *Cache) Set(key, value string) {
	if slot, ok := c.index[key]; ok {
		c.entries[slot].value = value
		c.moveToFront(slot)
		return
	}
	if len(c.index) >= c.capacity {
		c.release(c.tail)
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
	c.release(slot)
	return true
}

func (c *Cache) release(slot int32) {
	c.unlink(slot)
	e := &c.entries[slot]
	delete(c.index, e.key)
	*e = entry{}
	c.free = append(c.free, slot)
}

func (c *Cache) unlink(slot int32) {
	e := &c.entries[slot]
	if e.prev == nilSlot {
		c.head = e.next
	} else {
		c.entries[e.prev].next = e.next
	}
	if e.next == nilSlot {
		c.tail = e.prev
	} else {
		c.entries[e.next].prev = e.prev
	}
}

func (c *Cache) pushFront(slot int32) {
	e := &c.entries[slot]
	e.prev = nilSlot
	e.next = c.head
	if c.head == nilSlot {
		c.tail = slot
	} else {
		c.entries[c.head].prev = slot
	}
	c.head = slot
}

func (c *Cache) moveToFront(slot int32) {
	if slot == c.head {
		return
	}
	c.unlink(slot)
	c.pushFront(slot)
}
