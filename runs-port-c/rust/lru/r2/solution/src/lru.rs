//! A fixed-capacity LRU cache over borrowed byte-slice keys and values.
//!
//! Entries live in a slab (`Vec<Node>`) and are threaded into a doubly linked
//! recency list by index; a `HashMap` maps each key to its slab index. Every
//! operation runs in O(1) expected time.

use std::collections::HashMap;
use std::collections::hash_map::Entry;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

/// Upper bound on slots reserved up front, so a huge declared capacity does
/// not allocate memory that the input never uses.
const MAX_PREALLOC: usize = 1 << 16;

#[derive(Debug)]
struct Node<'a> {
    key: &'a [u8],
    value: &'a [u8],
    /// Neighbour towards the most recently used end, or `NIL`.
    prev: usize,
    /// Neighbour towards the least recently used end, or `NIL`.
    next: usize,
}

/// A least-recently-used cache holding at most `capacity` keys.
#[derive(Debug)]
pub struct LruCache<'a> {
    capacity: usize,
    index: HashMap<&'a [u8], usize>,
    nodes: Vec<Node<'a>>,
    /// Slab indices of removed nodes, available for reuse.
    free: Vec<usize>,
    /// Most recently used node, or `NIL`.
    head: usize,
    /// Least recently used node, or `NIL`.
    tail: usize,
}

impl<'a> LruCache<'a> {
    /// Creates an empty cache. A capacity of zero is treated as one.
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.max(1);
        let reserve = capacity.min(MAX_PREALLOC);
        Self {
            capacity,
            index: HashMap::with_capacity(reserve),
            nodes: Vec::with_capacity(reserve),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of keys currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Inserts or overwrites `key`, making it the most recently used. Evicts
    /// the least recently used key if the cache would exceed its capacity.
    pub fn set(&mut self, key: &'a [u8], value: &'a [u8]) {
        if let Some(&idx) = self.index.get(key) {
            self.nodes[idx].value = value;
            self.touch(idx);
            return;
        }

        if self.len() == self.capacity {
            self.evict_lru();
        }

        let node = Node { key, value, prev: NIL, next: NIL };
        let idx = match self.free.pop() {
            Some(idx) => {
                self.nodes[idx] = node;
                idx
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.index.insert(key, idx);
        self.push_front(idx);
    }

    /// Looks up `key`; a hit makes it the most recently used.
    pub fn get(&mut self, key: &[u8]) -> Option<&'a [u8]> {
        let idx = *self.index.get(key)?;
        self.touch(idx);
        Some(self.nodes[idx].value)
    }

    /// Removes `key`, returning whether it was present.
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
        let idx = self.tail;
        debug_assert_ne!(idx, NIL, "evicting from an empty cache");
        if let Entry::Occupied(slot) = self.index.entry(self.nodes[idx].key) {
            slot.remove();
        }
        self.release(idx);
    }

    /// Unlinks node `idx` from the recency list and recycles its slot.
    fn release(&mut self, idx: usize) {
        self.unlink(idx);
        self.free.push(idx);
    }

    fn touch(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
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
    }

    fn push_front(&mut self, idx: usize) {
        let old_head = self.head;
        let node = &mut self.nodes[idx];
        node.prev = NIL;
        node.next = old_head;
        match old_head {
            NIL => self.tail = idx,
            h => self.nodes[h].prev = idx,
        }
        self.head = idx;
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
    fn remove_and_reuse() {
        let mut c = LruCache::new(3);
        c.set(b"x", b"1");
        assert!(c.remove(b"x"));
        assert!(!c.remove(b"x"));
        assert_eq!(c.len(), 0);
        c.set(b"y", b"2");
        c.set(b"z", b"3");
        c.set(b"w", b"4");
        c.set(b"v", b"5");
        assert_eq!(c.len(), 3);
        assert_eq!(c.get(b"y"), None);
        assert_eq!(c.get(b"v"), Some(&b"5"[..]));
    }

    #[test]
    fn capacity_one() {
        let mut c = LruCache::new(1);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        assert_eq!(c.get(b"a"), None);
        assert_eq!(c.get(b"b"), Some(&b"2"[..]));
        assert_eq!(c.len(), 1);
    }
}
