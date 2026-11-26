//! A fixed-capacity least-recently-used cache with O(1) expected-time operations.
//!
//! Entries live in a slab (`Vec<Node>`) and are threaded onto an intrusive
//! doubly linked list ordered from most to least recently used. A hash map
//! from key to slab index gives constant-time lookup; freed slots are recycled.

use std::collections::HashMap;
use std::hash::Hash;

const NIL: usize = usize::MAX;

struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

pub struct LruCache<K, V> {
    capacity: usize,
    map: HashMap<K, usize>,
    nodes: Vec<Node<K, V>>,
    free: Vec<usize>,
    /// Most recently used entry.
    head: usize,
    /// Least recently used entry.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache that holds at most `capacity` entries.
    ///
    /// # Panics
    ///
    /// Panics if `capacity` is zero.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
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

    /// Returns the value for `key`, marking it as most recently used.
    pub fn get(&mut self, key: &K) -> Option<&V> {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, marking it as most recently used and
    /// evicting the least recently used entry if the capacity is exceeded.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&idx) = self.map.get(&key) {
            self.nodes[idx].value = value;
            self.move_to_front(idx);
            return;
        }
        if self.map.len() == self.capacity {
            self.evict_lru();
        }
        let node = Node {
            key: key.clone(),
            value,
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
        self.push_front(idx);
        self.map.insert(key, idx);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &K) -> bool {
        match self.map.remove(key) {
            Some(idx) => {
                self.unlink(idx);
                self.free.push(idx);
                true
            }
            None => false,
        }
    }

    fn evict_lru(&mut self) {
        let idx = self.tail;
        if idx == NIL {
            return;
        }
        self.unlink(idx);
        self.map.remove(&self.nodes[idx].key);
        self.free.push(idx);
    }

    fn move_to_front(&mut self, idx: usize) {
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
        let Node { prev, next, .. } = self.nodes[idx];
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
    use super::LruCache;

    #[test]
    fn evicts_least_recently_used() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.get(&"a"), Some(&1));
        c.put("c", 3);
        assert_eq!(c.get(&"b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_and_remove_recycles() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        c.put("a", 9);
        c.put("c", 3);
        assert_eq!(c.get(&"a"), Some(&9));
        assert_eq!(c.get(&"b"), None);
        assert!(c.remove(&"a"));
        assert!(!c.remove(&"a"));
        c.put("d", 4);
        assert_eq!(c.len(), 2);
        assert_eq!(c.get(&"c"), Some(&3));
    }
}
