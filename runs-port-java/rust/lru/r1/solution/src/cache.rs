//! A fixed-capacity least-recently-used cache.
//!
//! Entries live in a slab of nodes linked into an intrusive doubly linked
//! list (most recently used at the head), indexed by a hash map from key to
//! slot. Lookups, insertions, overwrites, removals and evictions all run in
//! O(1) expected time.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

/// Upper bound on the number of slots reserved up front, so a huge capacity
/// does not allocate memory that may never be used.
const MAX_INITIAL_CAPACITY: usize = 1 << 16;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// A least-recently-used cache holding at most `capacity` entries.
///
/// Both [`LruCache::get`] and [`LruCache::put`] mark the key as most recently
/// used. Inserting beyond capacity evicts the least recently used entry.
#[derive(Debug)]
pub struct LruCache<K, V> {
    capacity: usize,
    index: HashMap<K, usize>,
    nodes: Vec<Node<K, V>>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache.
    ///
    /// # Panics
    ///
    /// Panics if `capacity` is zero.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "capacity must be positive: {capacity}");
        let initial = capacity.min(MAX_INITIAL_CAPACITY);
        Self {
            capacity,
            index: HashMap::with_capacity(initial),
            nodes: Vec::with_capacity(initial),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Returns the number of entries currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns the value for `key`, if present; a hit refreshes its recency.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.nodes[slot].value)
    }

    /// Inserts or overwrites `key`, making it the most recently used entry and
    /// evicting the least recently used one if the cache exceeds capacity.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.nodes[slot].value = value;
            self.move_to_front(slot);
            return;
        }

        if self.index.len() == self.capacity {
            self.evict_lru();
        }

        let node = Node {
            key: key.clone(),
            value,
            prev: NIL,
            next: NIL,
        };
        let slot = match self.free.pop() {
            Some(slot) => {
                self.nodes[slot] = node;
                slot
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.push_front(slot);
        self.index.insert(key, slot);
    }

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
        V: Default,
    {
        let slot = self.index.remove(key)?;
        self.unlink(slot);
        self.free.push(slot);
        Some(std::mem::take(&mut self.nodes[slot].value))
    }

    fn evict_lru(&mut self) {
        let slot = self.tail;
        if slot == NIL {
            return;
        }
        self.unlink(slot);
        self.index.remove(&self.nodes[slot].key);
        self.free.push(slot);
    }

    fn move_to_front(&mut self, slot: usize) {
        if self.head != slot {
            self.unlink(slot);
            self.push_front(slot);
        }
    }

    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        {
            let node = &mut self.nodes[slot];
            node.prev = NIL;
            node.next = old_head;
        }
        if old_head == NIL {
            self.tail = slot;
        } else {
            self.nodes[old_head].prev = slot;
        }
        self.head = slot;
    }

    fn unlink(&mut self, slot: usize) {
        let Node { prev, next, .. } = self.nodes[slot];
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
        let node = &mut self.nodes[slot];
        node.prev = NIL;
        node.next = NIL;
    }
}

#[cfg(test)]
mod tests {
    use super::LruCache;

    #[test]
    fn evicts_least_recently_used() {
        let mut cache = LruCache::new(2);
        cache.put("a", 1);
        cache.put("b", 2);
        assert_eq!(cache.get("a"), Some(&1));
        cache.put("c", 3);
        assert_eq!(cache.get("b"), None);
        assert_eq!(cache.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut cache = LruCache::new(2);
        cache.put("a", 1);
        cache.put("b", 2);
        cache.put("a", 9);
        cache.put("c", 3);
        assert_eq!(cache.get("a"), Some(&9));
        assert_eq!(cache.get("b"), None);
        assert_eq!(cache.get("c"), Some(&3));
    }

    #[test]
    fn remove_frees_slot() {
        let mut cache = LruCache::new(1);
        cache.put("x", 1);
        assert_eq!(cache.remove("x"), Some(1));
        assert_eq!(cache.remove("x"), None);
        assert_eq!(cache.len(), 0);
        cache.put("y", 2);
        cache.put("z", 3);
        assert_eq!(cache.get("y"), None);
        assert_eq!(cache.get("z"), Some(&3));
        assert_eq!(cache.len(), 1);
    }
}
