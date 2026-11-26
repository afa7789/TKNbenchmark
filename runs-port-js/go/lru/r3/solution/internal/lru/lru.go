// Package lru implements a fixed-capacity least-recently-used cache.
package lru

const nilSlot = -1

// entry is a node of the intrusive doubly linked list ordering slots by recency.
type entry struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity LRU cache mapping string keys to string values.
// Entries live in a preallocated slice and are linked by index, so every
// operation runs in O(1) expected time without per-operation allocation
// beyond the stored strings. A Cache is not safe for concurrent use.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32
	head     int32 // most recently used
	tail     int32 // least recently used
}

// New returns an empty cache that holds at most capacity keys.
// It panics if capacity is less than 1.
func New(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be positive")
	}
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, capacity+1),
		entries:  make([]entry, 0, capacity+1),
		head:     nilSlot,
		tail:     nilSlot,
	}
}

// Len reports the number of keys held.
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
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value string) {
	if slot, ok := c.index[key]; ok {
		c.entries[slot].value = value
		c.moveToFront(slot)
		return
	}
	var slot int32
	if n := len(c.free); n > 0 {
		slot = c.free[n-1]
		c.free = c.free[:n-1]
		c.entries[slot] = entry{key: key, value: value}
	} else {
		slot = int32(len(c.entries))
		c.entries = append(c.entries, entry{key: key, value: value})
	}
	c.index[key] = slot
	c.pushFront(slot)
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key string) bool {
	slot, ok := c.index[key]
	if !ok {
		return false
	}
	c.remove(slot)
	return true
}

func (c *Cache) remove(slot int32) {
	c.unlink(slot)
	delete(c.index, c.entries[slot].key)
	c.entries[slot] = entry{} // release the strings
	c.free = append(c.free, slot)
}

func (c *Cache) pushFront(slot int32) {
	e := &c.entries[slot]
	e.prev = nilSlot
	e.next = c.head
	if c.head != nilSlot {
		c.entries[c.head].prev = slot
	} else {
		c.tail = slot
	}
	c.head = slot
}

func (c *Cache) unlink(slot int32) {
	e := &c.entries[slot]
	if e.prev != nilSlot {
		c.entries[e.prev].next = e.next
	} else {
		c.head = e.next
	}
	if e.next != nilSlot {
		c.entries[e.next].prev = e.prev
	} else {
		c.tail = e.prev
	}
}

func (c *Cache) moveToFront(slot int32) {
	if slot == c.head {
		return
	}
	c.unlink(slot)
	c.pushFront(slot)
}
