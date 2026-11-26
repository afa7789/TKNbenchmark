//! A fixed-capacity least-recently-used cache with O(1) expected-time operations.
//!
//! Entries live in a slab (`Vec<Node>`) and are threaded onto an intrusive
//! doubly linked list by index, ordered from least to most recently used.
//! A `HashMap` maps each key to its slot in the slab. Freed slots are recycled
//! through a free list, so the slab never grows beyond the peak number of
//! entries held.

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
    map: HashMap<K, usize>,
    nodes: Vec<Option<Node<K, V>>>,
    free: Vec<usize>,
    /// Least recently used entry.
    head: usize,
    /// Most recently used entry.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache. Inserting into a cache of capacity zero is a no-op.
    pub fn new(capacity: usize) -> Self {
        // Avoid huge up-front allocations for very large capacities.
        let initial = capacity.saturating_add(1).min(1 << 20);
        Self {
            capacity,
            map: HashMap::with_capacity(initial),
            nodes: Vec::with_capacity(initial),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.map.len()
    }

    /// Returns `true` if the cache holds no entries.
    #[allow(dead_code)]
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
        self.move_to_back(idx);
        Some(&self.node(idx).value)
    }

    /// Inserts or overwrites `key`, marking it most recently used, and evicts
    /// the least recently used entry if the cache exceeds its capacity.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&idx) = self.map.get(&key) {
            self.node_mut(idx).value = value;
            self.move_to_back(idx);
            return;
        }

        let idx = self.alloc(Node {
            key: key.clone(),
            value,
            prev: NIL,
            next: NIL,
        });
        self.map.insert(key, idx);
        self.push_back(idx);

        if self.map.len() > self.capacity {
            self.pop_front();
        }
    }

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = self.map.remove(key)?;
        Some(self.release(idx).value)
    }

    /// Evicts the least recently used entry, if any.
    fn pop_front(&mut self) -> Option<(K, V)> {
        if self.head == NIL {
            return None;
        }
        let node = self.release(self.head);
        self.map.remove(&node.key);
        Some((node.key, node.value))
    }

    fn node(&self, idx: usize) -> &Node<K, V> {
        self.nodes[idx].as_ref().expect("live slab slot")
    }

    fn node_mut(&mut self, idx: usize) -> &mut Node<K, V> {
        self.nodes[idx].as_mut().expect("live slab slot")
    }

    fn alloc(&mut self, node: Node<K, V>) -> usize {
        match self.free.pop() {
            Some(idx) => {
                self.nodes[idx] = Some(node);
                idx
            }
            None => {
                self.nodes.push(Some(node));
                self.nodes.len() - 1
            }
        }
    }

    /// Unlinks the node at `idx` and returns its slot to the free list.
    fn release(&mut self, idx: usize) -> Node<K, V> {
        self.unlink(idx);
        self.free.push(idx);
        self.nodes[idx].take().expect("live slab slot")
    }

    fn unlink(&mut self, idx: usize) {
        let (prev, next) = {
            let node = self.node(idx);
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

    fn push_back(&mut self, idx: usize) {
        let tail = self.tail;
        {
            let node = self.node_mut(idx);
            node.prev = tail;
            node.next = NIL;
        }
        match tail {
            NIL => self.head = idx,
            t => self.node_mut(t).next = idx,
        }
        self.tail = idx;
    }

    fn move_to_back(&mut self, idx: usize) {
        if self.tail != idx {
            self.unlink(idx);
            self.push_back(idx);
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
        c.put("z", 3);
        assert_eq!(c.len(), 2);
        assert_eq!(c.get("y"), Some(&2));
    }

    #[test]
    fn zero_capacity_holds_nothing() {
        let mut c = LruCache::new(0);
        c.put("a", 1);
        assert_eq!(c.len(), 0);
        assert_eq!(c.get("a"), None);
    }
}
