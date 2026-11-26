// Package lru implements a fixed-capacity least-recently-used cache.
//
// Entries live in a slice of nodes linked into an intrusive doubly linked
// list by index, with a map from key to node index. Every operation runs in
// O(1) expected time.
package lru

const nilSlot = -1

type node struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity LRU cache mapping strings to strings.
// The zero value is not usable; create one with New.
type Cache struct {
	capacity int
	index    map[string]int32
	nodes    []node
	head     int32 // most recently used
	tail     int32 // least recently used
	free     int32 // stack of reusable slots, linked through next
}

// New returns an empty cache that holds at most capacity entries.
// It panics if capacity is less than 1.
func New(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32),
		head:     nilSlot,
		tail:     nilSlot,
		free:     nilSlot,
	}
}

// Len reports the number of entries held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored for key and marks it most recently used.
func (c *Cache) Get(key string) (string, bool) {
	slot, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(slot)
	return c.nodes[slot].value, true
}

// GetBytes is like Get but takes the key as a byte slice, avoiding an
// allocation for the lookup.
func (c *Cache) GetBytes(key []byte) (string, bool) {
	slot, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(slot)
	return c.nodes[slot].value, true
}

// Set stores value under key and marks it most recently used, evicting the
// least recently used entry if the cache would exceed its capacity.
func (c *Cache) Set(key, value string) {
	if slot, ok := c.index[key]; ok {
		c.nodes[slot].value = value
		c.moveToFront(slot)
		return
	}
	if len(c.index) >= c.capacity {
		c.evict()
	}
	slot := c.allocate()
	c.nodes[slot].key = key
	c.nodes[slot].value = value
	c.index[key] = slot
	c.pushFront(slot)
}

// SetBytes is like Set but takes byte slices. The slices are copied only
// when needed, so callers may reuse them afterwards.
func (c *Cache) SetBytes(key, value []byte) {
	if slot, ok := c.index[string(key)]; ok {
		c.nodes[slot].value = string(value)
		c.moveToFront(slot)
		return
	}
	c.Set(string(key), string(value))
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

// DeleteBytes is like Delete but takes the key as a byte slice.
func (c *Cache) DeleteBytes(key []byte) bool {
	slot, ok := c.index[string(key)]
	if !ok {
		return false
	}
	c.remove(slot)
	return true
}

func (c *Cache) evict() { c.remove(c.tail) }

func (c *Cache) remove(slot int32) {
	delete(c.index, c.nodes[slot].key)
	c.unlink(slot)
	c.release(slot)
}

func (c *Cache) allocate() int32 {
	if c.free != nilSlot {
		slot := c.free
		c.free = c.nodes[slot].next
		return slot
	}
	c.nodes = append(c.nodes, node{})
	return int32(len(c.nodes) - 1)
}

func (c *Cache) release(slot int32) {
	// Drop references so the strings can be collected.
	c.nodes[slot] = node{prev: nilSlot, next: c.free}
	c.free = slot
}

func (c *Cache) pushFront(slot int32) {
	n := &c.nodes[slot]
	n.prev = nilSlot
	n.next = c.head
	if c.head != nilSlot {
		c.nodes[c.head].prev = slot
	} else {
		c.tail = slot
	}
	c.head = slot
}

func (c *Cache) unlink(slot int32) {
	n := &c.nodes[slot]
	if n.prev != nilSlot {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != nilSlot {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
}

func (c *Cache) moveToFront(slot int32) {
	if slot == c.head {
		return
	}
	c.unlink(slot)
	c.pushFront(slot)
}
