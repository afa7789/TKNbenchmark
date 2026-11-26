package main

import (
	"bufio"
	"bytes"
	"io"
	"strconv"
)

// lruCache is a fixed-capacity LRU cache. Entries live in a slice and are
// linked by index into a circular doubly linked list whose sentinel is
// node 0; the sentinel's next is the most recently used entry and its prev
// the least recently used. Slots released by Del are chained through next
// into a free list rooted at free (0 means empty).
type lruCache struct {
	capacity int
	index    map[string]int32
	nodes    []lruNode
	free     int32
}

type lruNode struct {
	key, value string
	prev, next int32
}

func newLRU(capacity int) *lruCache {
	hint := min(capacity, 1<<16)
	return &lruCache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		nodes:    make([]lruNode, 1, hint+1),
	}
}

// Len returns the number of keys held.
func (c *lruCache) Len() int { return len(c.index) }

// Get returns the value for key and marks it most recently used.
func (c *lruCache) Get(key []byte) (string, bool) {
	i, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// Set inserts or overwrites key, marks it most recently used and evicts the
// least recently used key if the cache is over capacity.
func (c *lruCache) Set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		c.nodes[i].value = string(value)
		c.moveToFront(i)
		return
	}

	var i int32
	switch {
	case len(c.index) >= c.capacity:
		// Evict the least recently used entry and reuse its slot.
		i = c.nodes[0].prev
		c.unlink(i)
		delete(c.index, c.nodes[i].key)
	case c.free != 0:
		i = c.free
		c.free = c.nodes[i].next
	default:
		c.nodes = append(c.nodes, lruNode{})
		i = int32(len(c.nodes) - 1)
	}

	k := string(key)
	c.nodes[i].key, c.nodes[i].value = k, string(value)
	c.index[k] = i
	c.pushFront(i)
}

// Del removes key and reports whether it was present.
func (c *lruCache) Del(key []byte) bool {
	i, ok := c.index[string(key)]
	if !ok {
		return false
	}
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = lruNode{next: c.free}
	c.free = i
	return true
}

func (c *lruCache) moveToFront(i int32) {
	if c.nodes[0].next != i {
		c.unlink(i)
		c.pushFront(i)
	}
}

func (c *lruCache) unlink(i int32) {
	n := &c.nodes[i]
	c.nodes[n.prev].next = n.next
	c.nodes[n.next].prev = n.prev
}

func (c *lruCache) pushFront(i int32) {
	first := c.nodes[0].next
	c.nodes[i].prev, c.nodes[i].next = 0, first
	c.nodes[first].prev = i
	c.nodes[0].next = i
}

// lruSim reads a capacity line followed by cache commands from r and writes
// the command results to w. Malformed command lines are ignored.
func lruSim(r io.Reader, w *bufio.Writer) error {
	br := bufio.NewReaderSize(r, 1<<20)

	first, err := readLine(br)
	if err != nil && err != io.EOF {
		return err
	}
	capacity, perr := strconv.Atoi(string(bytes.TrimSpace(first)))
	if perr != nil || capacity < 1 {
		return nil // no valid capacity, so there is nothing to simulate
	}
	cache := newLRU(capacity)

	for err == nil {
		var line []byte
		line, err = readLine(br)
		if err != nil && err != io.EOF {
			return err
		}
		execLRU(cache, line, w)
	}
	return nil
}

func execLRU(c *lruCache, line []byte, w *bufio.Writer) {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		if key, value, ok := bytes.Cut(rest, []byte{' '}); ok {
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
		if c.Del(rest) {
			w.WriteString("1\n")
		} else {
			w.WriteString("0\n")
		}
	case "SIZE":
		w.WriteString(strconv.Itoa(c.Len()))
		w.WriteByte('\n')
	}
}

// readLine returns the next line without its "\n" or "\r\n" terminator.
// The returned slice is only valid until the next read. At end of input it
// returns the final (possibly empty) line together with io.EOF.
func readLine(br *bufio.Reader) ([]byte, error) {
	line, err := br.ReadSlice('\n')
	if err == bufio.ErrBufferFull {
		buf := append([]byte(nil), line...)
		for err == bufio.ErrBufferFull {
			line, err = br.ReadSlice('\n')
			buf = append(buf, line...)
		}
		line = buf
	}
	line = bytes.TrimSuffix(line, []byte{'\n'})
	line = bytes.TrimSuffix(line, []byte{'\r'})
	return line, err
}
