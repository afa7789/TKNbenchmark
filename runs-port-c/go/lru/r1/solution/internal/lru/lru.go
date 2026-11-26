// Package lru implements a fixed-capacity least-recently-used cache with
// O(1) expected time for every operation.
//
// Entries live in a slice-backed pool and are linked into a doubly linked
// recency list by 32-bit index, which keeps nodes compact and avoids a heap
// allocation per entry. Index 0 is a sentinel acting as the list head.
package lru

const sentinel int32 = 0

type node struct {
	key   string
	value string
	prev  int32 // towards most recently used
	next  int32 // towards least recently used
}

// Cache maps string keys to string values, holding at most Capacity keys.
// The zero value is not usable; create caches with New.
type Cache struct {
	nodes    []node           // nodes[0] is the list sentinel
	index    map[string]int32 // key -> node index
	free     []int32          // recycled node indices
	capacity int
}

// New returns a cache that holds at most capacity keys. sizeHint is an
// optional estimate of how many keys will be live at once; storage for
// min(capacity, sizeHint) entries is preallocated. A non-positive sizeHint
// means no estimate. New panics if capacity is not positive.
func New(capacity, sizeHint int) *Cache {
	if capacity <= 0 {
		panic("lru: capacity must be positive")
	}
	prealloc := capacity
	if sizeHint > 0 && sizeHint < prealloc {
		prealloc = sizeHint
	}
	c := &Cache{
		nodes:    make([]node, 1, prealloc+1),
		index:    make(map[string]int32, prealloc),
		capacity: capacity,
	}
	return c
}

// Len reports the number of keys currently held.
func (c *Cache) Len() int { return len(c.index) }

// Capacity reports the maximum number of keys the cache holds.
func (c *Cache) Capacity() int { return c.capacity }

// Set inserts or overwrites key; it becomes the most recently used. If the
// cache would exceed its capacity, the least recently used key is evicted.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.moveToFront(i)
		return
	}

	// Evicting before inserting is observably identical to inserting and
	// then evicting, and keeps the pool bounded by the capacity.
	if len(c.index) >= c.capacity {
		c.remove(c.nodes[sentinel].prev)
	}

	i := c.alloc()
	n := &c.nodes[i]
	n.key = key
	n.value = value
	c.index[key] = i
	c.pushFront(i)
}

// Get returns the value for key and reports whether it was present. A hit
// makes the key the most recently used.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
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
	if n := len(c.free); n > 0 {
		i := c.free[n-1]
		c.free = c.free[:n-1]
		return i
	}
	c.nodes = append(c.nodes, node{})
	return int32(len(c.nodes) - 1)
}

func (c *Cache) remove(i int32) {
	n := &c.nodes[i]
	delete(c.index, n.key)
	c.unlink(i)
	*n = node{} // drop references so the strings can be collected
	c.free = append(c.free, i)
}

func (c *Cache) unlink(i int32) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

func (c *Cache) pushFront(i int32) {
	head := &c.nodes[sentinel]
	n := &c.nodes[i]
	n.prev = sentinel
	n.next = head.next
	c.nodes[head.next].prev = i
	head.next = i
}

func (c *Cache) moveToFront(i int32) {
	if c.nodes[sentinel].next == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}
