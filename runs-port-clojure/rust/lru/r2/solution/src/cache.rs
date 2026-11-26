//! A fixed-capacity least-recently-used cache with O(1) expected-time operations.
//!
//! Entries live in a slab (`Vec<Node>`) threaded by an intrusive doubly linked
//! list ordered from least to most recently used; a `HashMap` maps each key to
//! its slab slot. Freed slots are recycled through a free list.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

/// Sentinel index meaning "no node".
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
    capacity: usize,
    index: HashMap<K, usize>,
    nodes: Vec<Option<Node<K, V>>>,
    free: Vec<usize>,
    /// Least recently used node.
    head: usize,
    /// Most recently used node.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache. A capacity of zero is treated as one.
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.max(1);
        // Cap the up-front reservation; the structures grow on demand anyway.
        let reserve = capacity.min(1 << 20);
        Self {
            capacity,
            index: HashMap::with_capacity(reserve),
            nodes: Vec::with_capacity(reserve),
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

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.touch(slot);
        Some(&self.node(slot).value)
    }

    /// Inserts or overwrites `key`, making it most recently used, and evicts the
    /// least recently used entry if the capacity is exceeded.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.node_mut(slot).value = value;
            self.touch(slot);
            return;
        }

        let node = Node { key: key.clone(), value, prev: NIL, next: NIL };
        let slot = match self.free.pop() {
            Some(slot) => {
                self.nodes[slot] = Some(node);
                slot
            }
            None => {
                self.nodes.push(Some(node));
                self.nodes.len() - 1
            }
        };
        self.push_back(slot);
        self.index.insert(key, slot);

        if self.index.len() > self.capacity {
            self.evict_lru();
        }
    }

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = self.index.remove(key)?;
        Some(self.release(slot).value)
    }

    fn evict_lru(&mut self) {
        if self.head == NIL {
            return;
        }
        let node = self.release(self.head);
        self.index.remove(&node.key);
    }

    /// Unlinks `slot` and returns its node, recycling the slot.
    fn release(&mut self, slot: usize) -> Node<K, V> {
        self.unlink(slot);
        self.free.push(slot);
        self.nodes[slot].take().expect("released slot must be occupied")
    }

    fn touch(&mut self, slot: usize) {
        if slot != self.tail {
            self.unlink(slot);
            self.push_back(slot);
        }
    }

    fn unlink(&mut self, slot: usize) {
        let (prev, next) = {
            let node = self.node(slot);
            (node.prev, node.next)
        };
        match prev {
            NIL => self.head = next,
            p => self.node_mut(p).next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.node_mut(n).prev = prev,
        }
    }

    fn push_back(&mut self, slot: usize) {
        let old_tail = self.tail;
        {
            let node = self.node_mut(slot);
            node.prev = old_tail;
            node.next = NIL;
        }
        match old_tail {
            NIL => self.head = slot,
            t => self.node_mut(t).next = slot,
        }
        self.tail = slot;
    }

    fn node(&self, slot: usize) -> &Node<K, V> {
        self.nodes[slot].as_ref().expect("linked slot must be occupied")
    }

    fn node_mut(&mut self, slot: usize) -> &mut Node<K, V> {
        self.nodes[slot].as_mut().expect("linked slot must be occupied")
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
    fn overwrite_refreshes_recency() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        c.put("a", 9);
        c.put("c", 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
        assert_eq!(c.get("c"), Some(&3));
    }

    #[test]
    fn remove_and_reuse_slots() {
        let mut c = LruCache::new(3);
        c.put("x", 1);
        assert_eq!(c.remove("x"), Some(1));
        assert_eq!(c.remove("x"), None);
        assert!(c.is_empty());
        c.put("y", 2);
        assert_eq!(c.get("y"), Some(&2));
        assert_eq!(c.len(), 1);
    }
}
