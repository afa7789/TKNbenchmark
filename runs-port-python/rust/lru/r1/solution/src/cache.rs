//! A fixed-capacity least-recently-used cache with O(1) expected-time operations.
//!
//! Entries live in a dense `Vec` and are threaded onto an intrusive doubly linked
//! list by index (most recently used at the head). A `HashMap` maps each key to
//! its slot. Removal uses `swap_remove`, patching the links of the entry that
//! moved into the vacated slot, so the storage never contains holes.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;

/// Sentinel index marking the absence of a neighbour.
const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// A least-recently-used cache holding at most `capacity` entries.
#[derive(Debug)]
pub struct LruCache<K, V> {
    map: HashMap<K, usize>,
    nodes: Vec<Node<K, V>>,
    /// Most recently used entry.
    head: usize,
    /// Least recently used entry.
    tail: usize,
    capacity: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache that holds at most `capacity` entries.
    pub fn new(capacity: usize) -> Self {
        Self {
            map: HashMap::new(),
            nodes: Vec::new(),
            head: NIL,
            tail: NIL,
            capacity,
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    /// Returns `true` if the cache holds no entries.
    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }

    /// Looks up `key`, marking it as most recently used on a hit.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, making it the most recently used entry.
    /// Evicts the least recently used entry if the capacity is exceeded.
    pub fn put(&mut self, key: K, value: V) {
        if let Some(&idx) = self.map.get(&key) {
            self.nodes[idx].value = value;
            self.move_to_front(idx);
            return;
        }

        let idx = self.nodes.len();
        self.map.insert(key.clone(), idx);
        self.nodes.push(Node {
            key,
            value,
            prev: NIL,
            next: NIL,
        });
        self.link_front(idx);

        if self.nodes.len() > self.capacity {
            let lru = self.tail;
            self.remove_at(lru);
        }
    }

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = *self.map.get(key)?;
        Some(self.remove_at(idx))
    }

    /// Removes the entry stored at slot `idx` and returns its value.
    fn remove_at(&mut self, idx: usize) -> V {
        self.unlink(idx);
        let node = self.nodes.swap_remove(idx);
        self.map.remove(&node.key);

        // The former last node (if any) now occupies `idx`; repoint its neighbours.
        if idx < self.nodes.len() {
            let Node { prev, next, .. } = self.nodes[idx];
            match prev {
                NIL => self.head = idx,
                p => self.nodes[p].next = idx,
            }
            match next {
                NIL => self.tail = idx,
                n => self.nodes[n].prev = idx,
            }
            if let Some(slot) = self.map.get_mut(&self.nodes[idx].key) {
                *slot = idx;
            }
        }
        node.value
    }

    fn move_to_front(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.link_front(idx);
        }
    }

    fn link_front(&mut self, idx: usize) {
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
    fn remove_keeps_structure_consistent() {
        let mut c = LruCache::new(4);
        for (i, k) in ["a", "b", "c", "d"].into_iter().enumerate() {
            c.put(k, i);
        }
        assert_eq!(c.remove("a"), Some(0));
        assert_eq!(c.remove("a"), None);
        assert_eq!(c.remove("c"), Some(2));
        c.put("e", 4);
        c.put("f", 5);
        c.put("g", 6);
        assert_eq!(c.len(), 4);
        assert_eq!(c.get("b"), None);
        assert_eq!(c.get("d"), Some(&3));
        assert_eq!(c.get("e"), Some(&4));
        assert!(!c.is_empty());
    }

    #[test]
    fn capacity_one() {
        let mut c = LruCache::new(1);
        c.put("a", 1);
        c.put("b", 2);
        assert_eq!(c.get("a"), None);
        assert_eq!(c.get("b"), Some(&2));
        assert_eq!(c.len(), 1);
    }
}
