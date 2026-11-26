package main

// entry is a node in the cache's intrusive doubly linked recency list.
type entry struct {
	key, value string
	prev, next *entry
}

// Cache is a fixed-capacity least-recently-used cache. All operations run in
// O(1) expected time.
type Cache struct {
	capacity int
	index    map[string]*entry
	// root is a sentinel: root.next is the most recently used entry and
	// root.prev the least recently used one.
	root entry
}

// NewCache returns an empty cache holding at most capacity keys.
func NewCache(capacity int) *Cache {
	c := &Cache{
		capacity: capacity,
		index:    make(map[string]*entry, min(capacity+1, 1<<20)),
	}
	c.root.next = &c.root
	c.root.prev = &c.root
	return c
}

// Set inserts or overwrites key, marking it most recently used, and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *Cache) Set(key, value []byte) {
	if e, ok := c.index[string(key)]; ok {
		e.value = string(value)
		c.moveToFront(e)
		return
	}
	e := &entry{key: string(key), value: string(value)}
	c.index[e.key] = e
	c.pushFront(e)
	if len(c.index) > c.capacity {
		lru := c.root.prev
		c.unlink(lru)
		delete(c.index, lru.key)
	}
}

// Get returns the value for key and marks it most recently used.
func (c *Cache) Get(key []byte) (string, bool) {
	e, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(e)
	return e.value, true
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key []byte) bool {
	e, ok := c.index[string(key)]
	if !ok {
		return false
	}
	c.unlink(e)
	delete(c.index, e.key)
	return true
}

// Len returns the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

func (c *Cache) pushFront(e *entry) {
	e.prev = &c.root
	e.next = c.root.next
	c.root.next.prev = e
	c.root.next = e
}

func (c *Cache) unlink(e *entry) {
	e.prev.next = e.next
	e.next.prev = e.prev
	e.prev, e.next = nil, nil
}

func (c *Cache) moveToFront(e *entry) {
	if c.root.next == e {
		return
	}
	c.unlink(e)
	c.pushFront(e)
}
