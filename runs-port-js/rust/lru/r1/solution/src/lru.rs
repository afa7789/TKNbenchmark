//! Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
//! linked list stored in a slot arena. All operations are O(1) expected.

use std::collections::HashMap;
use std::hash::Hash;

const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Entry<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// A least-recently-used cache holding at most `capacity` entries.
#[derive(Debug)]
pub struct LruCache<K, V> {
    capacity: usize,
    index: HashMap<K, usize>,
    slots: Vec<Entry<K, V>>,
    free: Vec<usize>,
    /// Most recently used slot.
    head: usize,
    /// Least recently used slot.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache. A capacity of zero is treated as one.
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity: capacity.max(1),
            index: HashMap::new(),
            slots: Vec::new(),
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
    pub fn get(&mut self, key: &K) -> Option<&V> {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.slots[slot].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and
    /// evicting the least recently used entry if the cache would overflow.
    pub fn set(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.slots[slot].value = value;
            self.move_to_front(slot);
            return;
        }

        let slot = if self.index.len() >= self.capacity {
            // Reuse the evicted slot in place.
            let slot = self.tail;
            self.unlink(slot);
            let entry = &mut self.slots[slot];
            self.index.remove(&entry.key);
            entry.key = key.clone();
            entry.value = value;
            slot
        } else if let Some(slot) = self.free.pop() {
            let entry = &mut self.slots[slot];
            entry.key = key.clone();
            entry.value = value;
            slot
        } else {
            self.slots.push(Entry {
                key: key.clone(),
                value,
                prev: NIL,
                next: NIL,
            });
            self.slots.len() - 1
        };

        self.index.insert(key, slot);
        self.push_front(slot);
    }

    /// Removes `key`, returning `true` if it was present.
    pub fn remove(&mut self, key: &K) -> bool {
        let Some(slot) = self.index.remove(key) else {
            return false;
        };
        self.unlink(slot);
        self.free.push(slot);
        true
    }

    fn unlink(&mut self, slot: usize) {
        let Entry { prev, next, .. } = self.slots[slot];
        if prev == NIL {
            self.head = next;
        } else {
            self.slots[prev].next = next;
        }
        if next == NIL {
            self.tail = prev;
        } else {
            self.slots[next].prev = prev;
        }
    }

    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        let entry = &mut self.slots[slot];
        entry.prev = NIL;
        entry.next = old_head;
        if old_head == NIL {
            self.tail = slot;
        } else {
            self.slots[old_head].prev = slot;
        }
        self.head = slot;
    }

    fn move_to_front(&mut self, slot: usize) {
        if slot != self.head {
            self.unlink(slot);
            self.push_front(slot);
        }
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
        assert_eq!(cache.get(&"a"), Some(&1));
        cache.set("c", 3);
        assert_eq!(cache.get(&"b"), None);
        assert_eq!(cache.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut cache = LruCache::new(2);
        cache.set("a", 1);
        cache.set("b", 2);
        cache.set("a", 9);
        cache.set("c", 3);
        assert_eq!(cache.get(&"a"), Some(&9));
        assert_eq!(cache.get(&"b"), None);
        assert_eq!(cache.get(&"c"), Some(&3));
    }

    #[test]
    fn remove_frees_slot() {
        let mut cache = LruCache::new(1);
        cache.set("x", 1);
        assert!(cache.remove(&"x"));
        assert!(!cache.remove(&"x"));
        assert!(cache.is_empty());
        cache.set("y", 2);
        assert_eq!(cache.get(&"y"), Some(&2));
    }
}
