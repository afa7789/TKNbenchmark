//! A fixed-capacity least-recently-used cache with O(1) expected operations.
//!
//! Entries live in a slab (`Vec<Node>`) and are threaded onto an intrusive
//! doubly linked list by index; a `HashMap` maps keys to slab slots.

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
    /// Most recently used.
    head: usize,
    /// Least recently used.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache holding at most `capacity` entries.
    ///
    /// # Panics
    /// Panics if `capacity` is zero.
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
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and
    /// evicting the least recently used entry if over capacity.
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
            Some(i) => {
                self.nodes[i] = node;
                i
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
    pub fn remove<Q>(&mut self, key: &Q) -> bool
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
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
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.get("a"), Some(&1));
        c.put("c", 3);
        assert_eq!(c.get("b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes() {
        let mut c = LruCache::new(2);
        c.put("a", 1);
        c.put("b", 2);
        c.put("a", 9);
        c.put("c", 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
    }

    #[test]
    fn remove_and_reuse_slots() {
        let mut c = LruCache::new(1);
        c.put("x", 1);
        assert!(c.remove("x"));
        assert!(!c.remove("x"));
        assert_eq!(c.len(), 0);
        c.put("y", 2);
        c.put("z", 3);
        assert_eq!(c.get("y"), None);
        assert_eq!(c.get("z"), Some(&3));
    }
}
