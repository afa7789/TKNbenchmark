// Package lru implements the lru subcommand: an LRU cache simulator driven
// by commands read from its input.
package lru

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"strconv"
)

// maxCapacity is the largest capacity accepted on the first input line.
const maxCapacity = 1_000_000

// Run executes the lru subcommand, reading from r and writing to w.
//
// The first line holds the cache capacity; every later line is one of
// SET, GET, DEL or SIZE. Blank lines and unrecognised commands are ignored.
func Run(r io.Reader, w io.Writer) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)

	if !sc.Scan() {
		if err := sc.Err(); err != nil {
			return err
		}
		return errors.New("missing capacity line")
	}
	capacity, err := strconv.Atoi(string(bytes.TrimSpace(sc.Bytes())))
	if err != nil {
		return fmt.Errorf("invalid capacity: %w", err)
	}
	if capacity < 1 || capacity > maxCapacity {
		return fmt.Errorf("capacity %d out of range [1, %d]", capacity, maxCapacity)
	}

	c := newCache(capacity)
	bw, ok := w.(*bufio.Writer)
	if !ok {
		bw = bufio.NewWriter(w)
	}
	for sc.Scan() {
		if err := execute(c, bytes.TrimSuffix(sc.Bytes(), []byte{'\r'}), bw); err != nil {
			return err
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return bw.Flush()
}

// execute runs a single command line against c, writing any output to w.
func execute(c *cache, line []byte, w *bufio.Writer) error {
	cmd, rest, _ := bytes.Cut(line, []byte{' '})
	switch string(cmd) {
	case "SET":
		key, value, ok := bytes.Cut(rest, []byte{' '})
		if !ok || len(key) == 0 {
			return nil
		}
		c.set(key, value)
		return nil
	case "GET":
		value, ok := c.get(rest)
		if !ok {
			_, err := w.WriteString("NULL\n")
			return err
		}
		w.WriteString(value)
		return w.WriteByte('\n')
	case "DEL":
		if c.del(rest) {
			_, err := w.WriteString("1\n")
			return err
		}
		_, err := w.WriteString("0\n")
		return err
	case "SIZE":
		w.Write(strconv.AppendInt(w.AvailableBuffer(), int64(c.len()), 10))
		return w.WriteByte('\n')
	}
	return nil
}

// nilIndex marks the absence of a node in the intrusive list.
const nilIndex = -1

// node is an entry of the recency list. Nodes live in a slice and link to
// each other by index, which keeps them compact and free of GC pointers
// beyond the key and value strings.
type node struct {
	key, value string
	prev, next int32
}

// cache is a fixed-capacity LRU cache. Every operation runs in O(1)
// expected time: a map locates a key's node, and a doubly linked list
// ordered from most (head) to least (tail) recently used tracks recency.
type cache struct {
	capacity   int
	index      map[string]int32
	nodes      []node
	free       []int32 // slots of deleted nodes available for reuse
	head, tail int32
}

func newCache(capacity int) *cache {
	// Avoid committing memory for a huge capacity up front; the map and
	// node slice grow on demand.
	hint := min(capacity, 1<<16)
	return &cache{
		capacity: capacity,
		index:    make(map[string]int32, hint),
		nodes:    make([]node, 0, hint),
		head:     nilIndex,
		tail:     nilIndex,
	}
}

func (c *cache) len() int { return len(c.index) }

// get returns the value stored under key and marks it most recently used.
func (c *cache) get(key []byte) (string, bool) {
	i, ok := c.index[string(key)]
	if !ok {
		return "", false
	}
	c.moveToFront(i)
	return c.nodes[i].value, true
}

// set stores value under key, marks it most recently used and evicts the
// least recently used key if the cache exceeds its capacity.
func (c *cache) set(key, value []byte) {
	if i, ok := c.index[string(key)]; ok {
		n := &c.nodes[i]
		if n.value != string(value) {
			n.value = string(value)
		}
		c.moveToFront(i)
		return
	}

	if len(c.index) >= c.capacity {
		// Evict the tail and reuse its slot for the new key.
		i := c.tail
		c.unlink(i)
		delete(c.index, c.nodes[i].key)
		c.insert(i, key, value)
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
	c.insert(i, key, value)
}

// del removes key and reports whether it was present.
func (c *cache) del(key []byte) bool {
	i, ok := c.index[string(key)]
	if !ok {
		return false
	}
	c.unlink(i)
	delete(c.index, c.nodes[i].key)
	c.nodes[i] = node{}
	c.free = append(c.free, i)
	return true
}

// insert fills slot i with a new entry and links it at the front.
func (c *cache) insert(i int32, key, value []byte) {
	k := string(key)
	c.nodes[i] = node{key: k, value: string(value)}
	c.index[k] = i
	c.pushFront(i)
}

func (c *cache) moveToFront(i int32) {
	if c.head == i {
		return
	}
	c.unlink(i)
	c.pushFront(i)
}

func (c *cache) pushFront(i int32) {
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

func (c *cache) unlink(i int32) {
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
