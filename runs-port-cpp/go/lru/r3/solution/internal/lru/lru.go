// Package lru implements a fixed-capacity least-recently-used cache with
// O(1) expected-time operations.
package lru

// nilIdx marks the absence of a node in the intrusive list.
const nilIdx = -1

type node struct {
	key, value string
	prev, next int
}

// Cache is an LRU cache mapping string keys to string values. Entries are
// stored in a slice-backed doubly linked list (front = most recently used)
// so that nodes are reused rather than reallocated. The zero value is not
// usable; create caches with New.
type Cache struct {
	capacity   int
	index      map[string]int
	nodes      []node
	free       []int
	head, tail int
}

// New returns an empty cache holding at most capacity keys. A capacity of
// zero or less yields a cache that never retains anything.
func New(capacity int) *Cache {
	hint := max(capacity, 0) + 1
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int, hint),
		nodes:    make([]node, 0, hint),
		head:     nilIdx,
		tail:     nilIdx,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Set inserts or overwrites key, making it the most recently used. If the
// cache then exceeds its capacity, the least recently used key is evicted.
func (c *Cache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		c.nodes[i].value = string(value)
		c.moveToFront(i)
		return
	}
	i := c.alloc(string(key), string(value))
	c.index[c.nodes[i].key] = i
	c.pushFront(i)
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
}

// Get returns the value for key and whether it was present. A hit makes the
// key the most recently used.
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
	n := node{key: key, value: value, prev: nilIdx, next: nilIdx}
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
	c.nodes[i] = node{prev: nilIdx, next: nilIdx}
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
	n.prev = nilIdx
	n.next = c.head
	if c.head != nilIdx {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int) {
	n := &c.nodes[i]
	if n.prev != nilIdx {
		c.nodes[n.prev].next = n.next
	} else {
		c.head = n.next
	}
	if n.next != nilIdx {
		c.nodes[n.next].prev = n.prev
	} else {
		c.tail = n.prev
	}
	n.prev, n.next = nilIdx, nilIdx
}
