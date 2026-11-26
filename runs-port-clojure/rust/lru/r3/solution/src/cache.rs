//! A bounded least-recently-used cache with O(1) expected-time operations.
//!
//! Entries live in a slab (`Vec<Node>`) and are threaded onto an intrusive
//! doubly-linked recency list by index; a `HashMap` maps keys to slab slots.
//! Freed slots are recycled through a free list, so the slab never grows past
//! `capacity + 1` entries.

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
    nodes: Vec<Node<K, V>>,
    /// Most recently used node.
    head: usize,
    /// Least recently used node.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache. A capacity of zero is treated as one.
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.max(1);
        // Cap the up-front reservation so huge capacities don't allocate eagerly.
        let reserve = capacity.saturating_add(1).min(1 << 20);
        Self {
            capacity,
            index: HashMap::with_capacity(reserve),
            nodes: Vec::with_capacity(reserve),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns `true` if the cache holds no entries.
    #[allow(dead_code)] // Part of the container API; the binary only needs `len`.
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = *self.index.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used. If the cache
    /// then exceeds its capacity, the least recently used entry is evicted and
    /// returned.
    pub fn put(&mut self, key: K, value: V) -> Option<(K, V)> {
        if let Some(&idx) = self.index.get(&key) {
            self.nodes[idx].value = value;
            self.move_to_front(idx);
            return None;
        }

        let idx = self.alloc(key.clone(), value);
        self.index.insert(key, idx);
        self.push_front(idx);

        if self.index.len() > self.capacity {
            self.pop_back()
        } else {
            None
        }
    }

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = self.index.remove(key)?;
        self.unlink(idx);
        Some(self.release(idx).1)
    }

    /// Evicts and returns the least recently used entry.
    fn pop_back(&mut self) -> Option<(K, V)> {
        let idx = self.tail;
        if idx == NIL {
            return None;
        }
        self.unlink(idx);
        let (key, value) = self.release(idx);
        self.index.remove(&key);
        Some((key, value))
    }

    fn alloc(&mut self, key: K, value: V) -> usize {
        self.nodes.push(Node {
            key,
            value,
            prev: NIL,
            next: NIL,
        });
        self.nodes.len() - 1
    }

    /// Removes the (already unlinked) node at `idx` from the slab, moving the
    /// last node into its slot to keep the slab dense.
    fn release(&mut self, idx: usize) -> (K, V) {
        let node = self.nodes.swap_remove(idx);
        if idx < self.nodes.len() {
            self.relocated_to(idx);
        }
        (node.key, node.value)
    }

    /// Repoints the list neighbours and index entry of the node that was just
    /// moved into slot `to`.
    fn relocated_to(&mut self, to: usize) {
        let Node { prev, next, .. } = self.nodes[to];
        match prev {
            NIL => self.head = to,
            p => self.nodes[p].next = to,
        }
        match next {
            NIL => self.tail = to,
            n => self.nodes[n].prev = to,
        }
        if let Some(slot) = self.index.get_mut(&self.nodes[to].key) {
            *slot = to;
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

    fn move_to_front(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evicts_least_recently_used() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.get("a"), Some(&1));
        assert_eq!(c.put("c", 3), Some(("b", 2)));
        assert_eq!(c.get("b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.put("a", 9), None);
        c.put("c", 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
        assert_eq!(c.get("c"), Some(&3));
    }

    #[test]
    fn remove_and_reuse() {
        let mut c = LruCache::new(3);
        c.put("x", 1);
        c.put("y", 2);
        c.put("z", 3);
        assert_eq!(c.remove("x"), Some(1));
        assert_eq!(c.remove("x"), None);
        c.put("w", 4);
        c.put("v", 5);
        assert_eq!(c.get("y"), None);
        assert_eq!(c.get("z"), Some(&3));
        assert_eq!(c.get("w"), Some(&4));
        assert_eq!(c.get("v"), Some(&5));
        assert_eq!(c.len(), 3);
    }

    #[test]
    fn capacity_one() {
        let mut c = LruCache::new(1);
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.get("a"), None);
        assert_eq!(c.get("b"), Some(&2));
        assert_eq!(c.remove("b"), Some(2));
        assert!(c.is_empty());
    }
}
