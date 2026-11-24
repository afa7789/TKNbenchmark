//! A fixed-capacity LRU cache backed by a hash map and an index-linked list.

use std::collections::HashMap;

const NIL: usize = usize::MAX;

struct Node {
    key: Box<[u8]>,
    value: Box<[u8]>,
    prev: usize,
    next: usize,
}

/// Least-recently-used cache with O(1) expected-time operations.
///
/// Entries live in a slab (`nodes`) and are threaded into a doubly linked
/// list ordered from most recently used (`head`) to least (`tail`).
/// Slots freed by deletion are recycled through `free`.
pub struct LruCache {
    capacity: usize,
    map: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
}

impl LruCache {
    /// Creates an empty cache. `capacity` must be at least 1.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "capacity must be positive");
        Self {
            capacity,
            map: HashMap::new(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    pub fn len(&self) -> usize {
        self.map.len()
    }

    /// Returns the value for `key`, marking it most recently used.
    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and
    /// evicting the least recently used entry if over capacity.
    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&idx) = self.map.get(key) {
            self.nodes[idx].value = value.into();
            self.move_to_front(idx);
            return;
        }

        if self.map.len() == self.capacity {
            let lru = self.tail;
            self.unlink(lru);
            self.map.remove(&self.nodes[lru].key);
            self.free.push(lru);
        }

        let node = Node {
            key: key.into(),
            value: value.into(),
            prev: NIL,
            next: NIL,
        };
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
        self.map.insert(key.into(), idx);
        self.push_front(idx);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        let Some(idx) = self.map.remove(key) else {
            return false;
        };
        self.unlink(idx);
        let node = &mut self.nodes[idx];
        node.key = Box::default();
        node.value = Box::default();
        self.free.push(idx);
        true
    }

    fn move_to_front(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
        }
    }

    fn unlink(&mut self, idx: usize) {
        let (prev, next) = (self.nodes[idx].prev, self.nodes[idx].next);
        match prev {
            NIL => self.head = next,
            p => self.nodes[p].next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.nodes[n].prev = prev,
        }
        self.nodes[idx].prev = NIL;
        self.nodes[idx].next = NIL;
    }

    fn push_front(&mut self, idx: usize) {
        self.nodes[idx].prev = NIL;
        self.nodes[idx].next = self.head;
        match self.head {
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
    fn remove_and_reuse_slots() {
        let mut c = LruCache::new(2);
        c.set(b"a", b"1");
        assert!(c.remove(b"a"));
        assert!(!c.remove(b"a"));
        c.set(b"b", b"2");
        c.set(b"c", b"3");
        c.set(b"d", b"4");
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.get(b"c"), Some(&b"3"[..]));
        assert_eq!(c.len(), 2);
    }
}
