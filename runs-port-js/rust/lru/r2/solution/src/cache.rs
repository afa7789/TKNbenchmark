//! Fixed-capacity LRU cache: a hash map from key to slot index plus an
//! intrusive doubly linked list stored in a slot vector. Every operation is
//! O(1) expected.

use std::collections::HashMap;

/// Index of the list sentinel: `next` of the sentinel is the most recently
/// used entry, `prev` the least recently used.
const SENTINEL: usize = 0;

#[derive(Debug, Default)]
struct Slot {
    key: Vec<u8>,
    value: Vec<u8>,
    prev: usize,
    next: usize,
}

#[derive(Debug)]
pub struct LruCache {
    capacity: usize,
    index: HashMap<Vec<u8>, usize>,
    slots: Vec<Slot>,
    free: Vec<usize>,
}

impl LruCache {
    /// Creates an empty cache holding at most `capacity` keys.
    ///
    /// # Panics
    /// Panics if `capacity` is zero.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
        Self {
            capacity,
            index: HashMap::new(),
            slots: vec![Slot::default()],
            free: Vec::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.index.len()
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let slot = *self.index.get(key)?;
        self.touch(slot);
        Some(&self.slots[slot].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and
    /// evicting the least recently used entry if the cache overflows.
    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&slot) = self.index.get(key) {
            let entry = &mut self.slots[slot].value;
            entry.clear();
            entry.extend_from_slice(value);
            self.touch(slot);
            return;
        }
        if self.index.len() == self.capacity {
            let lru = self.slots[SENTINEL].prev;
            self.remove_slot(lru);
        }
        let slot = self.alloc_slot();
        let entry = &mut self.slots[slot];
        entry.key.extend_from_slice(key);
        entry.value.extend_from_slice(value);
        self.index.insert(key.to_vec(), slot);
        self.push_front(slot);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.get(key) {
            Some(&slot) => {
                self.remove_slot(slot);
                true
            }
            None => false,
        }
    }

    fn alloc_slot(&mut self) -> usize {
        self.free.pop().unwrap_or_else(|| {
            self.slots.push(Slot::default());
            self.slots.len() - 1
        })
    }

    fn remove_slot(&mut self, slot: usize) {
        self.unlink(slot);
        let entry = &mut self.slots[slot];
        self.index.remove(entry.key.as_slice());
        entry.key.clear();
        entry.value.clear();
        self.free.push(slot);
    }

    fn touch(&mut self, slot: usize) {
        self.unlink(slot);
        self.push_front(slot);
    }

    fn unlink(&mut self, slot: usize) {
        let Slot { prev, next, .. } = self.slots[slot];
        self.slots[prev].next = next;
        self.slots[next].prev = prev;
    }

    fn push_front(&mut self, slot: usize) {
        let first = self.slots[SENTINEL].next;
        self.slots[slot].prev = SENTINEL;
        self.slots[slot].next = first;
        self.slots[first].prev = slot;
        self.slots[SENTINEL].next = slot;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evicts_least_recently_used() {
        let mut c = LruCache::new(2);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        assert_eq!(c.get(b"a"), Some(&b"1"[..]));
        c.set(b"c", b"3");
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_and_remove_works() {
        let mut c = LruCache::new(2);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        c.set(b"a", b"9");
        c.set(b"c", b"3");
        assert_eq!(c.get(b"a"), Some(&b"9"[..]));
        assert_eq!(c.get(b"b"), None);
        assert!(c.remove(b"a"));
        assert!(!c.remove(b"a"));
        assert_eq!(c.len(), 1);
        assert!(c.remove(b"c"));
        assert!(c.is_empty());
    }
}
