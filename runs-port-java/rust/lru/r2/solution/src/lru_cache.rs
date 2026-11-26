//! A fixed-capacity cache that evicts the least recently used entry.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

/// Upper bound on the number of slots reserved up front, so a huge capacity
/// does not allocate memory that may never be used.
const MAX_INITIAL_CAPACITY: usize = 1 << 16;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// A fixed-capacity LRU cache. All operations run in O(1) expected time.
///
/// Entries live in a slab of nodes linked into a doubly linked recency list
/// (head = least recently used, tail = most recently used); a hash map
/// indexes the slab by key. Freed slots are recycled through a free list.
pub struct LruCache<K, V> {
    capacity: usize,
    index: HashMap<K, usize>,
    nodes: Vec<Node<K, V>>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache holding at most `capacity` entries.
    ///
    /// # Panics
    ///
    /// Panics if `capacity` is zero.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity >= 1, "capacity must be positive: {capacity}");
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

    /// Inserts or overwrites a mapping, making the key the most recently used.
    /// Evicts the least recently used entry if the cache grows past capacity.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.nodes[slot].value = value;
            self.move_to_tail(slot);
            return;
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
        self.push_tail(slot);
        self.index.insert(key, slot);

        if self.index.len() > self.capacity {
            self.evict_head();
        }
    }

    /// Returns the value for the key, marking it most recently used, or
    /// `None` if absent.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.move_to_tail(slot);
        Some(&self.nodes[slot].value)
    }

    /// Removes the key, returning whether it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> bool
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        match self.index.remove(key) {
            Some(slot) => {
                self.unlink(slot);
                self.free.push(slot);
                true
            }
            None => false,
        }
    }

    /// Returns the number of entries held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns `true` if the cache holds no entries.
    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    fn evict_head(&mut self) {
        let slot = self.head;
        debug_assert_ne!(slot, NIL, "evicting from an empty list");
        self.unlink(slot);
        self.index.remove(&self.nodes[slot].key);
        self.free.push(slot);
    }

    fn move_to_tail(&mut self, slot: usize) {
        if self.tail != slot {
            self.unlink(slot);
            self.push_tail(slot);
        }
    }

    fn push_tail(&mut self, slot: usize) {
        let node = &mut self.nodes[slot];
        node.prev = self.tail;
        node.next = NIL;
        match self.tail {
            NIL => self.head = slot,
            tail => self.nodes[tail].next = slot,
        }
        self.tail = slot;
    }

    fn unlink(&mut self, slot: usize) {
        let Node { prev, next, .. } = self.nodes[slot];
        match prev {
            NIL => self.head = next,
            prev => self.nodes[prev].next = next,
        }
        match next {
            NIL => self.tail = prev,
            next => self.nodes[next].prev = prev,
        }
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
    fn remove_reports_presence_and_recycles_slots() {
        let mut cache = LruCache::new(3);
        cache.put("x", 1);
        assert!(cache.remove("x"));
        assert!(!cache.remove("x"));
        assert!(cache.is_empty());
        cache.put("y", 2);
        cache.put("z", 3);
        assert_eq!(cache.get("y"), Some(&2));
        assert_eq!(cache.len(), 2);
    }

    #[test]
    fn capacity_one() {
        let mut cache = LruCache::new(1);
        cache.put("a", 1);
        cache.put("b", 2);
        assert_eq!(cache.get("a"), None);
        assert_eq!(cache.get("b"), Some(&2));
        assert_eq!(cache.len(), 1);
    }
}
