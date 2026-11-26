// Package lru provides a fixed-capacity cache that evicts the least recently
// used entry. All operations run in O(1) expected time.
package lru

// entry is a node in the cache's intrusive doubly linked recency list.
type entry[K comparable, V any] struct {
	key        K
	value      V
	prev, next *entry[K, V]
}

// Cache is a least-recently-used cache. The zero value is not usable; create
// one with New. A Cache is not safe for concurrent use.
type Cache[K comparable, V any] struct {
	capacity int
	items    map[K]*entry[K, V]
	// root is a sentinel: root.next is the most recently used entry and
	// root.prev the least recently used one.
	root entry[K, V]
}

// maxInitialCapacity bounds the map preallocation so a huge capacity with few
// keys does not waste memory up front.
const maxInitialCapacity = 1 << 16

// New returns an empty cache holding at most capacity keys.
// It panics if capacity is less than 1.
func New[K comparable, V any](capacity int) *Cache[K, V] {
	if capacity < 1 {
		panic("lru: capacity must be positive")
	}
	c := &Cache[K, V]{
		capacity: capacity,
		items:    make(map[K]*entry[K, V], min(capacity, maxInitialCapacity)),
	}
	c.root.next = &c.root
	c.root.prev = &c.root
	return c
}

// Set inserts or overwrites the value for key, making it the most recently
// used. If the cache then exceeds its capacity, the least recently used key is
// evicted.
func (c *Cache[K, V]) Set(key K, value V) {
	if e, ok := c.items[key]; ok {
		e.value = value
		c.moveToFront(e)
		return
	}
	e := &entry[K, V]{key: key, value: value}
	c.items[key] = e
	c.pushFront(e)
	if len(c.items) > c.capacity {
		oldest := c.root.prev
		c.unlink(oldest)
		delete(c.items, oldest.key)
	}
}

// Get returns the value for key and whether it was present. A hit makes the
// key the most recently used.
func (c *Cache[K, V]) Get(key K) (V, bool) {
	e, ok := c.items[key]
	if !ok {
		var zero V
		return zero, false
	}
	c.moveToFront(e)
	return e.value, true
}

// Delete removes key and reports whether it was present.
func (c *Cache[K, V]) Delete(key K) bool {
	e, ok := c.items[key]
	if !ok {
		return false
	}
	c.unlink(e)
	delete(c.items, key)
	return true
}

// Len returns the number of keys held.
func (c *Cache[K, V]) Len() int {
	return len(c.items)
}

func (c *Cache[K, V]) pushFront(e *entry[K, V]) {
	e.prev = &c.root
	e.next = c.root.next
	c.root.next.prev = e
	c.root.next = e
}

func (c *Cache[K, V]) unlink(e *entry[K, V]) {
	e.prev.next = e.next
	e.next.prev = e.prev
	e.prev, e.next = nil, nil
}

func (c *Cache[K, V]) moveToFront(e *entry[K, V]) {
	if c.root.next == e {
		return
	}
	c.unlink(e)
	c.pushFront(e)
}
