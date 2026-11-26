package lru

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"strconv"
)

// MaxCapacity is the largest capacity accepted on the first input line.
const MaxCapacity = 1_000_000

// nilIndex marks the absence of a node in the intrusive list.
const nilIndex = -1

// node is an entry of the cache. Nodes live in a slice and link to each
// other by index, which keeps the list compact and free of per-entry
// pointers for the garbage collector to trace.
type node struct {
	key, value string
	prev, next int32
}

// Cache is a fixed-capacity LRU cache from string keys to string values.
// Every operation runs in O(1) expected time. The zero value is not usable;
// create caches with New.
type Cache struct {
	capacity int
	index    map[string]int32
	nodes    []node
	free     []int32 // indices of nodes released by Delete
	head     int32   // most recently used, or nilIndex
	tail     int32   // least recently used, or nilIndex
}

// New returns an empty cache holding at most capacity keys. It panics if
// capacity is not positive.
func New(capacity int) *Cache {
	if capacity < 1 {
		panic("lru: capacity must be positive")
	}
	hint := min(capacity, 1<<16)
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		nodes:    make([]node, 0, hint),
		head:     nilIndex,
		tail:     nilIndex,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value stored under key and marks key as the most recently
// used. The boolean reports whether the key was present.
func (c *Cache) Get(key string) (string, bool) {
	i, ok := c.index[key]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set stores value under key and marks key as the most recently used,
// evicting the least recently used key if the cache would exceed its
// capacity.
func (c *Cache) Set(key, value string) {
	if i, ok := c.index[key]; ok {
		c.nodes[i].value = value
		c.moveToFront(i)
		return
	}

	var i int32
	switch {
	case len(c.index) >= c.capacity:
		// Recycle the evicted node for the new entry.
		i = c.tail
		c.unlink(i)
		delete(c.index, c.nodes[i].key)
	case len(c.free) > 0:
		i = c.free[len(c.free)-1]
		c.free = c.free[:len(c.free)-1]
	default:
		i = int32(len(c.nodes))
		c.nodes = append(c.nodes, node{})
	}
	c.nodes[i] = node{key: key, value: value}
	c.index[key] = i
	c.pushFront(i)
}

// Delete removes key and reports whether it was present.
func (c *Cache) Delete(key string) bool {
	i, ok := c.index[key]
	if !ok {
		return false
	}
	c.unlink(i)
	delete(c.index, key)
	c.nodes[i] = node{} // drop string references
	c.free = append(c.free, i)
	return true
}

func (c *Cache) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *Cache) pushFront(i int32) {
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

func (c *Cache) unlink(i int32) {
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

// Run executes the lru subcommand, reading from r and writing to w.
//
// The first line holds the cache capacity; each later line is one command
// (SET, GET, DEL or SIZE). Blank and unrecognized lines are ignored.
func Run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64<<10), 1<<20)

	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return err
		}
		return errors.New("missing capacity line")
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil || capacity < 1 || capacity > MaxCapacity {
		return fmt.Errorf("invalid capacity %q: want an integer in [1, %d]", sc.Bytes(), MaxCapacity)
	}

	c := New(capacity)
	var out []byte // output of the current command, reused across commands
	for sc.Scan() {
		line := bytes.TrimSuffix(sc.Bytes(), []byte{'\r'})
		cmd, rest, _ := bytes.Cut(line, []byte{' '})
		out = out[:0]
		switch string(cmd) {
		case "SET":
			key, value, ok := bytes.Cut(rest, []byte{' '})
			if !ok {
				continue
			}
			c.Set(string(key), string(value))
			continue
		case "GET":
			if v, ok := c.Get(string(rest)); ok {
				out = append(out, v...)
			} else {
				out = append(out, "NULL"...)
			}
		case "DEL":
			if c.Delete(string(rest)) {
				out = append(out, '1')
			} else {
				out = append(out, '0')
			}
		case "SIZE":
			out = strconv.AppendInt(out, int64(c.Len()), 10)
		default:
			continue
		}
		out = append(out, '\n')
		if _, err := w.Write(out); err != nil {
			return err
		}
	}
	return sc.Err()
}
