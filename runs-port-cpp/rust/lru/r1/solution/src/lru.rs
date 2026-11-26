//! An LRU cache backed by a hash index and an intrusive doubly linked list
//! stored in a slab, giving O(1) expected time for every operation.

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

/// Least-recently-used cache over byte-string keys and values.
#[derive(Debug)]
pub struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    free: Vec<usize>,
    /// Most recently used node.
    head: usize,
    /// Least recently used node.
    tail: usize,
}

impl LruCache {
    /// Creates a cache that holds at most `capacity` keys.
    pub fn new(capacity: usize) -> Self {
        let reserve = capacity.saturating_add(1).min(1 << 20);
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

    /// Inserts or overwrites `key`, making it the most recently used, and
    /// evicts the least recently used key if the capacity is exceeded.
    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&idx) = self.index.get(key) {
            let node = &mut self.nodes[idx];
            node.value.clear();
            node.value.extend_from_slice(value);
            self.touch(idx);
            return;
        }

        let idx = self.alloc(Node {
            key: key.into(),
            value: value.to_vec(),
            prev: NIL,
            next: NIL,
        });
        self.index.insert(key.into(), idx);
        self.push_front(idx);

        if self.index.len() > self.capacity {
            let lru = self.tail;
            self.remove_node(lru);
        }
    }

    /// Looks up `key`; a hit makes it the most recently used.
    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let idx = *self.index.get(key)?;
        self.touch(idx);
        Some(&self.nodes[idx].value)
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.get(key) {
            Some(&idx) => {
                self.remove_node(idx);
                true
            }
            None => false,
        }
    }

    fn alloc(&mut self, node: Node) -> usize {
        match self.free.pop() {
            Some(idx) => {
                self.nodes[idx] = node;
                idx
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        }
    }

    /// Unlinks the node, drops it from the index, and recycles its slot.
    fn remove_node(&mut self, idx: usize) {
        self.unlink(idx);
        let node = &mut self.nodes[idx];
        let key = std::mem::take(&mut node.key);
        node.value = Vec::new();
        self.index.remove(&key);
        self.free.push(idx);
    }

    fn touch(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
        }
    }

    fn push_front(&mut self, idx: usize) {
        let old_head = self.head;
        {
            let node = &mut self.nodes[idx];
            node.prev = NIL;
            node.next = old_head;
        }
        if old_head == NIL {
            self.tail = idx;
        } else {
            self.nodes[old_head].prev = idx;
        }
        self.head = idx;
    }

    fn unlink(&mut self, idx: usize) {
        let (prev, next) = {
            let node = &self.nodes[idx];
            (node.prev, node.next)
        };
        if prev == NIL {
            self.head = next;
        } else {
            self.nodes[prev].next = next;
        }
        if next == NIL {
            self.tail = prev;
        } else {
            self.nodes[next].prev = prev;
        }
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
    fn overwrite_refreshes_and_remove() {
        let mut c = LruCache::new(2);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        c.set(b"a", b"9");
        c.set(b"c", b"3");
        assert_eq!(c.get(b"a"), Some(&b"9"[..]));
        assert_eq!(c.get(b"b"), None);
        assert!(c.remove(b"a"));
        assert!(!c.remove(b"a"));
        assert_eq!(c.len(), 1);
    }

    #[test]
    fn zero_capacity_holds_nothing() {
        let mut c = LruCache::new(0);
        c.set(b"a", b"1");
        assert_eq!(c.len(), 0);
        assert_eq!(c.get(b"a"), None);
    }
}
