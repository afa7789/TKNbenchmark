//! A fixed-capacity least-recently-used cache.
//!
//! Entries live in a slab (`Vec`) and are threaded onto an intrusive doubly
//! linked list by index: the head is the least recently used entry and the
//! tail the most recently used. A `HashMap` maps each key to its slot, so
//! every operation runs in O(1) expected time.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;
use std::num::NonZeroUsize;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

#[derive(Debug)]
pub struct LruCache<K, V> {
    capacity: NonZeroUsize,
    index: HashMap<K, usize>,
    slots: Vec<Option<Node<K, V>>>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    pub fn new(capacity: NonZeroUsize) -> Self {
        Self {
            capacity,
            index: HashMap::new(),
            slots: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of keys currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.unlink(slot);
        self.push_back(slot);
        Some(&self.node(slot).value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting
    /// the least recently used entry if the cache exceeds its capacity.
    pub fn set(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.node_mut(slot).value = value;
            self.unlink(slot);
            self.push_back(slot);
            return;
        }

        let slot = self.alloc(Node {
            key: key.clone(),
            value,
            prev: NIL,
            next: NIL,
        });
        self.index.insert(key, slot);
        self.push_back(slot);

        if self.index.len() > self.capacity.get() {
            let oldest = self.head;
            let node = self.remove_slot(oldest);
            self.index.remove(&node.key);
        }
    }

    /// Removes `key`; returns whether it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> bool
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        match self.index.remove(key) {
            Some(slot) => {
                self.remove_slot(slot);
                true
            }
            None => false,
        }
    }

    fn node(&self, slot: usize) -> &Node<K, V> {
        self.slots[slot].as_ref().expect("linked slot is occupied")
    }

    fn node_mut(&mut self, slot: usize) -> &mut Node<K, V> {
        self.slots[slot].as_mut().expect("linked slot is occupied")
    }

    fn alloc(&mut self, node: Node<K, V>) -> usize {
        match self.free.pop() {
            Some(slot) => {
                self.slots[slot] = Some(node);
                slot
            }
            None => {
                self.slots.push(Some(node));
                self.slots.len() - 1
            }
        }
    }

    /// Unlinks the node at `slot`, frees the slot and returns the node.
    fn remove_slot(&mut self, slot: usize) -> Node<K, V> {
        self.unlink(slot);
        self.free.push(slot);
        self.slots[slot].take().expect("linked slot is occupied")
    }

    fn unlink(&mut self, slot: usize) {
        let (prev, next) = {
            let node = self.node(slot);
            (node.prev, node.next)
        };
        if prev == NIL {
            self.head = next;
        } else {
            self.node_mut(prev).next = next;
        }
        if next == NIL {
            self.tail = prev;
        } else {
            self.node_mut(next).prev = prev;
        }
    }

    fn push_back(&mut self, slot: usize) {
        let tail = self.tail;
        {
            let node = self.node_mut(slot);
            node.prev = tail;
            node.next = NIL;
        }
        if tail == NIL {
            self.head = slot;
        } else {
            self.node_mut(tail).next = slot;
        }
        self.tail = slot;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cache(capacity: usize) -> LruCache<String, u32> {
        LruCache::new(NonZeroUsize::new(capacity).unwrap())
    }

    #[test]
    fn evicts_least_recently_used() {
        let mut c = cache(2);
        c.set("a".into(), 1);
        c.set("b".into(), 2);
        assert_eq!(c.get("a"), Some(&1));
        c.set("c".into(), 3);
        assert_eq!(c.get("b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes() {
        let mut c = cache(2);
        c.set("a".into(), 1);
        c.set("b".into(), 2);
        c.set("a".into(), 9);
        c.set("c".into(), 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
        assert_eq!(c.get("c"), Some(&3));
    }

    #[test]
    fn remove_and_reuse_slots() {
        let mut c = cache(3);
        c.set("x".into(), 1);
        assert!(c.remove("x"));
        assert!(!c.remove("x"));
        assert_eq!(c.len(), 0);
        c.set("y".into(), 2);
        c.set("z".into(), 3);
        assert_eq!(c.get("y"), Some(&2));
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn capacity_one() {
        let mut c = cache(1);
        c.set("a".into(), 1);
        c.set("b".into(), 2);
        assert_eq!(c.get("a"), None);
        assert_eq!(c.get("b"), Some(&2));
        assert_eq!(c.len(), 1);
    }
}
