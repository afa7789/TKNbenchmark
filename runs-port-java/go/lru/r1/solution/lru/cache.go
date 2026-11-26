// Package lru provides a fixed-capacity least-recently-used cache.
package lru

// maxInitialCapacity bounds the map preallocation so huge capacities do not
// reserve memory that may never be used.
const maxInitialCapacity = 1 << 16

type entry[K comparable, V any] struct {
	key        K
	value      V
	prev, next *entry[K, V]
}

// Cache is a fixed-capacity LRU cache. Get, Set and Delete all run in O(1)
// expected time. Both Get hits and Set mark the key as most recently used.
//
// A Cache is not safe for concurrent use.
type Cache[K comparable, V any] struct {
	capacity int
	entries  map[K]*entry[K, V]
	// root is a sentinel of a circular doubly linked list: root.next is the
	// most recently used entry and root.prev the least recently used.
	root entry[K, V]
}

// New returns an empty cache holding at most capacity keys. It panics if
// capacity is not positive.
func New[K comparable, V any](capacity int) *Cache[K, V] {
	if capacity < 1 {
		panic("lru: capacity must be positive")
	}
	c := &Cache[K, V]{
		capacity: capacity,
		entries:  make(map[K]*entry[K, V], min(capacity, maxInitialCapacity)),
	}
	c.root.prev = &c.root
	c.root.next = &c.root
	return c
}

// Get returns the value stored for key and whether it was present. A hit
// makes key the most recently used.
func (c *Cache[K, V]) Get(key K) (V, bool) {
	e, ok := c.entries[key]
	if !ok {
		var zero V
		return zero, false
	}
	c.moveToFront(e)
	return e.value, true
}

// Set inserts or overwrites key, making it the most recently used. If the
// cache then holds more than its capacity, the least recently used key is
// evicted.
func (c *Cache[K, V]) Set(key K, value V) {
	if e, ok := c.entries[key]; ok {
		e.value = value
		c.moveToFront(e)
		return
	}
	var e *entry[K, V]
	if len(c.entries) >= c.capacity {
		// Evict the oldest entry and recycle its node for the new key.
		e = c.root.prev
		c.unlink(e)
		delete(c.entries, e.key)
	} else {
		e = new(entry[K, V])
	}
	e.key, e.value = key, value
	c.pushFront(e)
	c.entries[key] = e
}

// Delete removes key and reports whether it was present.
func (c *Cache[K, V]) Delete(key K) bool {
	e, ok := c.entries[key]
	if !ok {
		return false
	}
	c.unlink(e)
	delete(c.entries, key)
	return true
}

// Len returns the number of keys held.
func (c *Cache[K, V]) Len() int {
	return len(c.entries)
}

func (c *Cache[K, V]) moveToFront(e *entry[K, V]) {
	if c.root.next == e {
		return
	}
	c.unlink(e)
	c.pushFront(e)
}

func (c *Cache[K, V]) unlink(e *entry[K, V]) {
	e.prev.next = e.next
	e.next.prev = e.prev
	e.prev, e.next = nil, nil
}

func (c *Cache[K, V]) pushFront(e *entry[K, V]) {
	e.prev = &c.root
	e.next = c.root.next
	c.root.next.prev = e
	c.root.next = e
}
