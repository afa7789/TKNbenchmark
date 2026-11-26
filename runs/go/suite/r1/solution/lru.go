package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"strconv"
)

const maxCapacity = 1_000_000

// nilIdx marks the absence of a neighbour in the intrusive list.
const nilIdx = -1

type lruEntry struct {
	key, value string
	prev, next int32
}

// lruCache is an LRU cache whose entries live in a slab indexed by int32,
// linked into a doubly linked list ordered from most to least recently used.
type lruCache struct {
	capacity   int
	index      map[string]int32
	entries    []lruEntry
	free       []int32
	head, tail int32 // most / least recently used
}

func newLRUCache(capacity int) *lruCache {
	return &lruCache{
		capacity: capacity,
		index:    make(map[string]int32, min(capacity, 1<<16)),
		head:     nilIdx,
		tail:     nilIdx,
	}
}

func (c *lruCache) Len() int { return len(c.index) }

func (c *lruCache) unlink(i int32) {
	e := &c.entries[i]
	if e.prev != nilIdx {
		c.entries[e.prev].next = e.next
	} else {
		c.head = e.next
	}
	if e.next != nilIdx {
		c.entries[e.next].prev = e.prev
	} else {
		c.tail = e.prev
	}
	e.prev, e.next = nilIdx, nilIdx
}

func (c *lruCache) pushFront(i int32) {
	e := &c.entries[i]
	e.prev, e.next = nilIdx, c.head
	if c.head != nilIdx {
		c.entries[c.head].prev = i
	} else {
		c.tail = i
	}
	c.head = i
}

func (c *lruCache) touch(i int32) {
	if c.head != i {
		c.unlink(i)
		c.pushFront(i)
	}
}

func (c *lruCache) remove(i int32) {
	c.unlink(i)
	delete(c.index, c.entries[i].key)
	c.entries[i] = lruEntry{prev: nilIdx, next: nilIdx}
	c.free = append(c.free, i)
}

// Get returns the value for key and marks it most recently used.
func (c *lruCache) Get(key []byte) (string, bool) {
	i, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.touch(i)
	return c.entries[i].value, true
}

// Set inserts or overwrites key, evicting the least recently used entry
// if the cache grows beyond its capacity.
func (c *lruCache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		c.entries[i].value = string(value)
		c.touch(i)
		return
	}
	var i int32
	if n := len(c.free); n > 0 {
		i = c.free[n-1]
		c.free = c.free[:n-1]
	} else {
		i = int32(len(c.entries))
		c.entries = append(c.entries, lruEntry{})
	}
	k := string(key)
	c.entries[i] = lruEntry{key: k, value: string(value)}
	c.index[k] = i
	c.pushFront(i)
	if len(c.index) > c.capacity {
		c.remove(c.tail)
	}
}

// Delete removes key and reports whether it was present.
func (c *lruCache) Delete(key []byte) bool {
	i, ok := c.index[string(key)]
	if ok {
		c.remove(i)
	}
	return ok
}

// lru runs the cache simulator: a capacity line followed by commands.
func lru(r io.Reader, w *bufio.Writer) error {
	var (
		cache  *lruCache
		parseE error
	)
	err := forEachLine(r, func(line []byte) {
		if parseE != nil {
			return
		}
		if cache == nil {
			capacity, err := strconv.Atoi(string(bytes.TrimSpace(line)))
			if err != nil || capacity < 1 || capacity > maxCapacity {
				parseE = fmt.Errorf("invalid capacity %q", line)
				return
			}
			cache = newLRUCache(capacity)
			return
		}
		runLRUCommand(cache, line, w)
	})
	if err != nil {
		return err
	}
	if parseE != nil {
		return parseE
	}
	if cache == nil {
		return errors.New("missing capacity line")
	}
	return nil
}

// runLRUCommand executes one command line; malformed lines are ignored.
func runLRUCommand(c *lruCache, line []byte, w *bufio.Writer) {
	line = bytes.TrimSuffix(line, []byte{'\r'})
	op, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(op) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if ok {
			c.Set(key, value)
		}
	case "GET":
		if v, ok := c.Get(rest); ok {
			w.WriteString(v)
		} else {
			w.WriteString("NULL")
		}
		w.WriteByte('\n')
	case "DEL":
		if c.Delete(rest) {
			w.WriteString("1\n")
		} else {
			w.WriteString("0\n")
		}
	case "SIZE":
		w.WriteString(strconv.Itoa(c.Len()))
		w.WriteByte('\n')
	}
}
