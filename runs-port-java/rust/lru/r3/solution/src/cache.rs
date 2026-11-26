//! A fixed-capacity cache that evicts the least recently used entry.
//!
//! Entries live in a slab of nodes linked into a doubly-linked recency list;
//! a hash map indexes the slab by key. All operations run in O(1) expected time.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// A least-recently-used cache holding at most `capacity` entries.
pub struct LruCache<K, V> {
    capacity: usize,
    index: HashMap<K, usize>,
    nodes: Vec<Option<Node<K, V>>>,
    free: Vec<usize>,
    /// Most recently used node.
    head: usize,
    /// Least recently used node.
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
        let initial = capacity.saturating_add(1).min(1 << 16);
        Self {
            capacity,
            index: HashMap::with_capacity(initial),
            nodes: Vec::with_capacity(initial),
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

    /// Inserts or overwrites a mapping, marking the key as most recently used.
    /// Evicts the least recently used entry if the capacity is exceeded.
    pub fn set(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.node_mut(slot).value = value;
            self.detach(slot);
            self.push_front(slot);
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
                self.nodes[slot] = Some(node);
                slot
            }
            None => {
                self.nodes.push(Some(node));
                self.nodes.len() - 1
            }
        };
        self.index.insert(key, slot);
        self.push_front(slot);

        if self.index.len() > self.capacity {
            let lru = self.tail;
            self.remove_slot(lru);
        }
    }

    /// Returns the value for `key`, marking it most recently used.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.detach(slot);
        self.push_front(slot);
        Some(&self.node(slot).value)
    }

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        Some(self.remove_slot(slot))
    }

    fn remove_slot(&mut self, slot: usize) -> V {
        self.detach(slot);
        let node = self.nodes[slot].take().expect("linked slot is occupied");
        self.index.remove(&node.key);
        self.free.push(slot);
        node.value
    }

    fn node(&self, slot: usize) -> &Node<K, V> {
        self.nodes[slot].as_ref().expect("linked slot is occupied")
    }

    fn node_mut(&mut self, slot: usize) -> &mut Node<K, V> {
        self.nodes[slot].as_mut().expect("linked slot is occupied")
    }

    /// Unlinks `slot` from the recency list.
    fn detach(&mut self, slot: usize) {
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
        let node = self.node_mut(slot);
        node.prev = NIL;
        node.next = NIL;
    }

    /// Links a detached `slot` in as the most recently used entry.
    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        {
            let node = self.node_mut(slot);
            node.prev = NIL;
            node.next = old_head;
        }
        match old_head {
            NIL => self.tail = slot,
            h => self.node_mut(h).prev = slot,
        }
        self.head = slot;
    }
}

#[cfg(test)]
mod tests {
    use super::LruCache;

    #[test]
    fn evicts_least_recently_used() {
        let mut cache = LruCache::new(2);
        cache.set("a", 1);
        cache.set("b", 2);
        assert_eq!(cache.get("a"), Some(&1));
        cache.set("c", 3);
        assert_eq!(cache.get("b"), None);
        assert_eq!(cache.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut cache = LruCache::new(2);
        cache.set("a", 1);
        cache.set("b", 2);
        cache.set("a", 9);
        cache.set("c", 3);
        assert_eq!(cache.get("a"), Some(&9));
        assert_eq!(cache.get("b"), None);
        assert_eq!(cache.get("c"), Some(&3));
    }

    #[test]
    fn remove_and_reuse_slots() {
        let mut cache = LruCache::new(1);
        cache.set("x", 1);
        assert_eq!(cache.remove("x"), Some(1));
        assert_eq!(cache.remove("x"), None);
        assert!(cache.is_empty());
        cache.set("y", 2);
        cache.set("z", 3);
        assert_eq!(cache.get("y"), None);
        assert_eq!(cache.get("z"), Some(&3));
        assert_eq!(cache.len(), 1);
    }
}
