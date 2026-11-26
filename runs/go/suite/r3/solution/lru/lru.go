// Package lru implements a fixed-capacity least-recently-used cache and a
// line-oriented command simulator on top of it.
package lru

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"strconv"
)

const nilIdx = -1

type node struct {
	key, value string
	prev, next int32
}

// Cache is an LRU cache of string keys and values. All operations are O(1)
// expected time. Nodes live in a slice and are linked by index, which keeps
// the structure compact and avoids per-entry heap allocations.
type Cache struct {
	capacity   int
	index      map[string]int32
	nodes      []node
	free       []int32
	head, tail int32 // head is most recently used
}

// New returns an empty cache that holds at most capacity keys (capacity ≥ 1).
func New(capacity int) *Cache {
	return &Cache{
		capacity: capacity,
		index:    make(map[string]int32, min(capacity, 1<<16)),
		head:     nilIdx,
		tail:     nilIdx,
	}
}

// Len reports the number of keys held.
func (c *Cache) Len() int { return len(c.index) }

// Get returns the value for key and marks it most recently used.
func (c *Cache) Get(key []byte) (string, bool) {
	i, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set inserts or overwrites key, marks it most recently used and evicts the
// least recently used key if the capacity is exceeded.
func (c *Cache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		if c.nodes[i].value != string(value) {
			c.nodes[i].value = string(value)
		}
		c.moveToFront(i)
		return
	}
	var i int32
	if n := len(c.free); n > 0 {
		i = c.free[n-1]
		c.free = c.free[:n-1]
	} else {
		i = int32(len(c.nodes))
		c.nodes = append(c.nodes, node{})
	}
	k := string(key)
	c.nodes[i] = node{key: k, value: string(value), prev: nilIdx, next: nilIdx}
	c.index[k] = i
	c.pushFront(i)
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
}

// Del removes key and reports whether it was present.
func (c *Cache) Del(key []byte) bool {
	i, ok := c.index[string(key)]
	if ok {
		c.remove(i)
	}
	return ok
}

func (c *Cache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = node{}
	c.free = append(c.free, i)
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
	n.prev, n.next = nilIdx, c.head
	if c.head != nilIdx {
		c.nodes[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *Cache) unlink(i int32) {
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

// Run reads a capacity line followed by SET/GET/DEL/SIZE commands from r and
// writes each command's output to w. Unrecognised lines are ignored.
func Run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 1<<16), 1<<20)

	if !sc.Scan() {
		return sc.Err()
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil || capacity < 1 {
		return fmt.Errorf("invalid capacity %q", sc.Bytes())
	}
	cache := New(capacity)

	var out []byte
	for sc.Scan() {
		line := bytes.TrimSuffix(sc.Bytes(), []byte{'\r'})
		cmd, rest, _ := bytes.Cut(line, []byte{' '})
		switch string(cmd) {
		case "SET":
			key, value, ok := bytes.Cut(rest, []byte{' '})
			if ok {
				cache.Set(key, value)
			}
			continue
		case "GET":
			if v, ok := cache.Get(rest); ok {
				out = append(out, v...)
			} else {
				out = append(out, "NULL"...)
			}
		case "DEL":
			if cache.Del(rest) {
				out = append(out, '1')
			} else {
				out = append(out, '0')
			}
		case "SIZE":
			out = strconv.AppendInt(out, int64(cache.Len()), 10)
		default:
			continue
		}
		out = append(out, '\n')
		if len(out) >= 1<<15 {
			if _, err := w.Write(out); err != nil {
				return err
			}
			out = out[:0]
		}
	}
	if err := sc.Err(); err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	_, err = w.Write(out)
	return err
}
