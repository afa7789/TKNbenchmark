//! Fixed-capacity least-recently-used cache with O(1) expected-time operations.

use std::collections::HashMap;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node {
    key: Box<[u8]>,
    value: Vec<u8>,
    prev: usize,
    next: usize,
}

/// An LRU cache over byte-string keys and values.
///
/// Entries are stored in a slab (`Vec<Node>`) and threaded into a doubly
/// linked list ordered from most (`head`) to least (`tail`) recently used.
/// Freed slots are recycled through `free`, so node indices stay stable and
/// the index map can refer to them directly.
#[derive(Debug)]
pub struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
}

impl LruCache {
    /// Creates an empty cache that holds at most `capacity` entries.
    pub fn new(capacity: usize) -> Self {
        // Cap the up-front reservation so absurd capacities cannot exhaust memory.
        let reserve = capacity.saturating_add(1).min(1 << 21);
        Self {
            capacity,
            index: HashMap::with_capacity(reserve),
            nodes: Vec::with_capacity(reserve),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Inserts or overwrites `key`, making it the most recently used entry.
    /// Evicts the least recently used entry if capacity is exceeded.
    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&idx) = self.index.get(key) {
            let node = &mut self.nodes[idx];
            node.value.clear();
            node.value.extend_from_slice(value);
            self.touch(idx);
            return;
        }

        let node = Node {
            key: key.into(),
            value: value.to_vec(),
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
        self.push_front(idx);
        self.index.insert(key.into(), idx);

        if self.index.len() > self.capacity {
            self.evict_oldest();
        }
    }

    /// Returns the value for `key` and marks it most recently used, or `None`
    /// on a miss.
    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let idx = *self.index.get(key)?;
        self.touch(idx);
        Some(&self.nodes[idx].value)
    }

    /// Removes `key`; returns whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.remove(key) {
            Some(idx) => {
                self.release(idx);
                true
            }
            None => false,
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    fn touch(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
        }
    }

    fn evict_oldest(&mut self) {
        let idx = self.tail;
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
        node.value = Vec::new();
        self.free.push(idx);
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

    fn push_front(&mut self, idx: usize) {
        let old_head = self.head;
        {
            let node = &mut self.nodes[idx];
            node.prev = NIL;
            node.next = old_head;
        }
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
    fn overwrite_refreshes() {
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
        assert_eq!(c.len(), 0);
        c.set(b"y", b"2");
        c.set(b"z", b"3");
        assert_eq!(c.get(b"y"), Some(&b"2"[..]));
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn zero_capacity_holds_nothing() {
        let mut c = LruCache::new(0);
        c.set(b"a", b"1");
        assert_eq!(c.get(b"a"), None);
        assert_eq!(c.len(), 0);
    }
}
