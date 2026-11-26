// Package lru implements a fixed-capacity least-recently-used cache with
// O(1) expected-time operations.
package lru

// nilIndex marks the absence of a node in the intrusive list.
const nilIndex = -1

// maxPrealloc bounds the up-front allocation derived from the capacity.
const maxPrealloc = 1 << 20

type node struct {
	key, value string
	prev, next int
}

// Cache is a least-recently-used cache mapping string keys to string values.
//
// Entries are stored in a slice-backed doubly linked list ordered from most
// to least recently used; freed slots are recycled, so steady-state
// operation does not allocate list nodes. The zero value is not usable;
// create caches with New.
type Cache struct {
	capacity int
	nodes    []node
	free     []int
	head     int // most recently used
	tail     int // least recently used
	index    map[string]int
}

// New returns an empty cache that holds at most capacity entries.
func New(capacity int) *Cache {
	hint := min(max(capacity, 0)+1, maxPrealloc)
	return &Cache{
		capacity: capacity,
		nodes:    make([]node, 0, hint),
		head:     nilIndex,
		tail:     nilIndex,
		index:    make(map[string]int, hint),
	}
}

// Len reports the number of entries held.
func (c *Cache) Len() int { return len(c.index) }

// Cap reports the maximum number of entries held.
func (c *Cache) Cap() int { return c.capacity }

// Set inserts or overwrites key, making it the most recently used entry.
// If the cache then exceeds its capacity, the least recently used entry
// is evicted.
func (c *Cache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		c.nodes[i].value = string(value)
		c.moveToFront(i)
		return
	}
	i := c.alloc(string(key), string(value))
	c.pushFront(i)
	c.index[c.nodes[i].key] = i
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
}

// Get returns the value for key and marks it most recently used.
// The boolean reports whether the key was present.
func (c *Cache) Get(key []byte) (string, bool) {
	i, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
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

func (c *Cache) alloc(key, value string) int {
	n := node{key: key, value: value, prev: nilIndex, next: nilIndex}
	if k := len(c.free); k > 0 {
		i := c.free[k-1]
		c.free = c.free[:k-1]
		c.nodes[i] = n
		return i
	}
	c.nodes = append(c.nodes, n)
	return len(c.nodes) - 1
}

// remove unlinks node i, drops it from the index and recycles its slot.
func (c *Cache) remove(i int) {
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = node{prev: nilIndex, next: nilIndex}
	c.free = append(c.free, i)
}

func (c *Cache) moveToFront(i int) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) pushFront(i int) {
	n := &c.nodes[i]
	n.prev = nilIndex
	n.next = c.head
	if c.head != nilIndex {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int) {
	n := &c.nodes[i]
	if n.prev != nilIndex {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != nilIndex {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
	n.prev, n.next = nilIndex, nilIndex
}
