//! A fixed-capacity least-recently-used cache with O(1) expected operations.
//!
//! Entries live in a slab (`Vec<Node>`) threaded by an intrusive doubly linked
//! list of indices, ordered from most to least recently used. A `HashMap` maps
//! each key to its slot.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// An LRU cache holding at most `capacity` entries.
#[derive(Debug)]
pub struct LruCache<K, V> {
    map: HashMap<K, usize>,
    nodes: Vec<Node<K, V>>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
    capacity: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache.
    ///
    /// # Panics
    /// Panics if `capacity` is zero.
    #[must_use]
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
        Self {
            map: HashMap::new(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
            capacity,
        }
    }

    /// Number of entries currently held.
    #[must_use]
    pub fn len(&self) -> usize {
        self.map.len()
    }

    /// Whether the cache holds no entries.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, making it most recently used and evicting
    /// the least recently used entry if the capacity is exceeded.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&idx) = self.map.get(&key) {
            self.nodes[idx].value = value;
            self.move_to_front(idx);
            return;
        }

        let idx = if self.map.len() >= self.capacity {
            // Reuse the evicted tail slot in place.
            let idx = self.tail;
            self.unlink(idx);
            let node = &mut self.nodes[idx];
            self.map.remove(&node.key);
            node.key = key.clone();
            node.value = value;
            idx
        } else {
            let node = Node { key: key.clone(), value, prev: NIL, next: NIL };
            if let Some(idx) = self.free.pop() {
                self.nodes[idx] = node;
                idx
            } else {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.push_front(idx);
        self.map.insert(key, idx);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> bool
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let Some(idx) = self.map.remove(key) else {
            return false;
        };
        self.unlink(idx);
        self.free.push(idx);
        true
    }

    fn unlink(&mut self, idx: usize) {
        let (prev, next) = (self.nodes[idx].prev, self.nodes[idx].next);
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

    fn push_front(&mut self, idx: usize) {
        let old_head = self.head;
        let node = &mut self.nodes[idx];
        node.prev = NIL;
        node.next = old_head;
        if old_head == NIL {
            self.tail = idx;
        } else {
            self.nodes[old_head].prev = idx;
        }
        self.head = idx;
    }

    fn move_to_front(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
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
        assert_eq!(c.get("a"), Some(&1));
        c.put("c", 3);
        assert_eq!(c.get("b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_and_remove_frees() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        c.put("a", 9);
        c.put("c", 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
        assert!(c.remove("a"));
        assert!(!c.remove("a"));
        c.put("d", 4);
        assert_eq!(c.len(), 2);
        assert_eq!(c.get("c"), Some(&3));
        assert_eq!(c.get("d"), Some(&4));
    }

    #[test]
    fn capacity_one() {
        let mut c = LruCache::new(1);
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.get("a"), None);
        assert_eq!(c.get("b"), Some(&2));
        assert!(c.remove("b"));
        assert!(c.is_empty());
    }
}
