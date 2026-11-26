//! A fixed-capacity least-recently-used cache with O(1) expected operations.
//!
//! Entries live in a slab (`Vec<Node>`) and are threaded onto an intrusive
//! doubly linked list ordered from least to most recently used. A hash map
//! from key to slab index provides constant-time lookup; freed slots are
//! recycled through a free list so the slab never grows beyond capacity + 1.

use std::collections::HashMap;

const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node {
    key: Box<[u8]>,
    value: Box<[u8]>,
    prev: usize,
    next: usize,
}

/// An LRU cache mapping byte-string keys to byte-string values.
#[derive(Debug)]
pub struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    free: Vec<usize>,
    /// Least recently used entry.
    head: usize,
    /// Most recently used entry.
    tail: usize,
}

impl LruCache {
    /// Creates a cache that holds at most `capacity` entries.
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            index: HashMap::new(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns `true` if the cache holds no entries.
    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    /// Looks up `key`, marking it as most recently used on a hit.
    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let idx = *self.index.get(key)?;
        self.touch(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, making it the most recently used entry.
    /// Evicts the least recently used entry if capacity is exceeded.
    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&idx) = self.index.get(key) {
            self.nodes[idx].value = value.into();
            self.touch(idx);
            return;
        }

        let key: Box<[u8]> = key.into();
        let node = Node {
            key: key.clone(),
            value: value.into(),
            prev: NIL,
            next: NIL,
        };
        let idx = match self.free.pop() {
            Some(slot) => {
                self.nodes[slot] = node;
                slot
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.index.insert(key, idx);
        self.push_back(idx);

        if self.len() > self.capacity {
            self.evict_lru();
        }
    }

    /// Removes `key`, returning `true` if it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.remove(key) {
            Some(idx) => {
                self.release(idx);
                true
            }
            None => false,
        }
    }

    fn evict_lru(&mut self) {
        let idx = self.head;
        if idx == NIL {
            return;
        }
        self.index.remove(&self.nodes[idx].key);
        self.release(idx);
    }

    /// Unlinks the node at `idx` and returns its slot to the free list.
    fn release(&mut self, idx: usize) {
        self.unlink(idx);
        let node = &mut self.nodes[idx];
        node.key = Box::default();
        node.value = Box::default();
        self.free.push(idx);
    }

    /// Moves the node at `idx` to the most-recently-used position.
    fn touch(&mut self, idx: usize) {
        if self.tail != idx {
            self.unlink(idx);
            self.push_back(idx);
        }
    }

    fn unlink(&mut self, idx: usize) {
        let Node { prev, next, .. } = self.nodes[idx];
        match prev {
            NIL => self.head = next,
            p => self.nodes[p].next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.nodes[n].prev = prev,
        }
        let node = &mut self.nodes[idx];
        node.prev = NIL;
        node.next = NIL;
    }

    fn push_back(&mut self, idx: usize) {
        let old_tail = self.tail;
        {
            let node = &mut self.nodes[idx];
            node.prev = old_tail;
            node.next = NIL;
        }
        match old_tail {
            NIL => self.head = idx,
            t => self.nodes[t].next = idx,
        }
        self.tail = idx;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evicts_least_recently_used() {
        let mut c = LruCache::new(2);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        assert_eq!(c.get(b"a"), Some(&b"1"[..]));
        c.set(b"c", b"3");
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut c = LruCache::new(2);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        c.set(b"a", b"9");
        c.set(b"c", b"3");
        assert_eq!(c.get(b"a"), Some(&b"9"[..]));
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.get(b"c"), Some(&b"3"[..]));
    }

    #[test]
    fn remove_and_reuse_slots() {
        let mut c = LruCache::new(3);
        c.set(b"x", b"1");
        assert!(c.remove(b"x"));
        assert!(!c.remove(b"x"));
        assert!(c.is_empty());
        c.set(b"y", b"2");
        assert_eq!(c.nodes.len(), 1);
        assert_eq!(c.get(b"y"), Some(&b"2"[..]));
    }

    #[test]
    fn zero_capacity_holds_nothing() {
        let mut c = LruCache::new(0);
        c.set(b"a", b"1");
        assert!(c.is_empty());
        assert_eq!(c.get(b"a"), None);
    }
}
