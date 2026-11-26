package lru

// Cache is a fixed-capacity least-recently-used cache mapping string keys to
// string values. Every operation runs in O(1) expected time.
//
// Entries live in a slice and are linked by index into a circular doubly
// linked list ordered from most to least recently used. Slot 0 is the list
// sentinel; freed slots are recycled through a free list, so the cache never
// holds more than capacity+1 slots and allocates no per-entry list nodes.
type Cache struct {
	capacity int
	index    map[string]int32
	entries  []entry
	free     []int32
}

type entry struct {
	key, value string
	prev, next int32
}

const sentinel = 0

// maxPrealloc bounds the up-front allocation so that a huge capacity paired
// with a short command stream does not reserve memory it never uses.
const maxPrealloc = 1 << 16

// NewCache returns an empty cache that holds at most capacity keys.
// It panics if capacity is less than 1.
func NewCache(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be at least 1")
	}
	hint := min(capacity, maxPrealloc)
	c := &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		entries:  make([]entry, 1, hint+1),
	}
	c.entries[sentinel] = entry{prev: sentinel, next: sentinel}
	return c
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored under key and marks key as the most recently
// used. ok is false if key is absent.
func (c *Cache) Get(key string) (value string, ok bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.entries[i].value, true
}

// Set stores value under key and marks key as the most recently used. If the
// cache then holds more than its capacity, the least recently used key is
// evicted.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.entries[i].value = value
		c.moveToFront(i)
		return
	}
	if len(c.index) >= c.capacity {
		c.remove(c.entries[sentinel].prev)
	}
	i := c.alloc()
	c.entries[i].key = key
	c.entries[i].value = value
	c.index[key] = i
	c.pushFront(i)
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
	c.entries = append(c.entries, entry{})
	return int32(len(c.entries) - 1)
}

// remove unlinks entry i, drops it from the index and recycles its slot.
func (c *Cache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.entries[i].key)
	c.entries[i] = entry{} // release the strings
	c.free = append(c.free, i)
}

func (c *Cache) moveToFront(i int32) {
	if c.entries[sentinel].next == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) unlink(i int32) {
	e := &c.entries[i]
	c.entries[e.prev].next = e.next
	c.entries[e.next].prev = e.prev
}

func (c *Cache) pushFront(i int32) {
	head := c.entries[sentinel].next
	c.entries[i].prev = sentinel
	c.entries[i].next = head
	c.entries[head].prev = i
	c.entries[sentinel].next = i
}
