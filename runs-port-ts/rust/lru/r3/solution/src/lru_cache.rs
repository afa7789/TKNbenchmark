//! Fixed-capacity LRU cache with O(1) expected-time operations.
//!
//! Entries live in a slab of slots; recency order is an intrusive doubly
//! linked list over slot indices, and a hash map resolves keys to slots.

use std::collections::HashMap;
use std::hash::Hash;

const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Slot<K, V> {
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
    slots: Vec<Option<Slot<K, V>>>,
    free: Vec<usize>,
    /// Most recently used slot.
    head: usize,
    /// Least recently used slot.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache.
    ///
    /// # Panics
    ///
    /// Panics if `capacity` is zero.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "capacity must be positive");
        Self {
            capacity,
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
    #[allow(dead_code)] // Kept alongside `len` for a complete API.
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    /// Looks up `key`; a hit marks it as the most recently used.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.slot(slot).value)
    }

    /// Inserts or overwrites `key`, making it the most recently used.
    /// Evicts the least recently used entry if the cache would overflow.
    pub fn set(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.slot_mut(slot).value = value;
            self.move_to_front(slot);
            return;
        }
        if self.index.len() >= self.capacity {
            self.evict_least_recent();
        }

        let entry = Slot {
            key: key.clone(),
            value,
            prev: NIL,
            next: NIL,
        };
        let slot = match self.free.pop() {
            Some(slot) => {
                self.slots[slot] = Some(entry);
                slot
            }
            None => {
                self.slots.push(Some(entry));
                self.slots.len() - 1
            }
        };
        self.index.insert(key, slot);
        self.push_front(slot);
    }

    /// Removes `key`, returning `true` if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> bool
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        match self.index.remove(key) {
            Some(slot) => {
                self.release(slot);
                true
            }
            None => false,
        }
    }

    fn evict_least_recent(&mut self) {
        if self.tail != NIL {
            let evicted = self.release(self.tail);
            self.index.remove(&evicted.key);
        }
    }

    /// Unlinks a slot and returns it to the free list, yielding its entry.
    /// The caller is responsible for removing the key from the index.
    fn release(&mut self, slot: usize) -> Slot<K, V> {
        self.unlink(slot);
        self.free.push(slot);
        self.slots[slot].take().expect("live slot")
    }

    fn slot(&self, slot: usize) -> &Slot<K, V> {
        self.slots[slot].as_ref().expect("live slot")
    }

    fn slot_mut(&mut self, slot: usize) -> &mut Slot<K, V> {
        self.slots[slot].as_mut().expect("live slot")
    }

    fn move_to_front(&mut self, slot: usize) {
        if slot != self.head {
            self.unlink(slot);
            self.push_front(slot);
        }
    }

    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        {
            let entry = self.slot_mut(slot);
            entry.prev = NIL;
            entry.next = old_head;
        }
        if old_head != NIL {
            self.slot_mut(old_head).prev = slot;
        }
        self.head = slot;
        if self.tail == NIL {
            self.tail = slot;
        }
    }

    fn unlink(&mut self, slot: usize) {
        let (prev, next) = {
            let entry = self.slot(slot);
            (entry.prev, entry.next)
        };
        if prev != NIL {
            self.slot_mut(prev).next = next;
        } else {
            self.head = next;
        }
        if next != NIL {
            self.slot_mut(next).prev = prev;
        } else {
            self.tail = prev;
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
    }

    #[test]
    fn remove_reports_presence() {
        let mut cache = LruCache::new(3);
        cache.set("x", 1);
        assert!(cache.remove("x"));
        assert!(!cache.remove("x"));
        assert!(cache.is_empty());
        cache.set("y", 2);
        assert_eq!(cache.get("y"), Some(&2));
    }
}
