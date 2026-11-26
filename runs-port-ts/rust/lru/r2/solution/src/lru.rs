//! Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
//! linked list stored in slot vectors. All operations are O(1) expected.

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
    slots: Vec<Option<Entry<K, V>>>,
    /// Most recently used slot.
    head: usize,
    /// Least recently used slot.
    tail: usize,
    /// Indices of vacated slots available for reuse.
    free: Vec<usize>,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache. Panics if `capacity` is zero.
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be at least 1");
        Self {
            capacity,
            index: HashMap::new(),
            slots: Vec::new(),
            head: NIL,
            tail: NIL,
            free: Vec::new(),
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Looks up `key`; a hit marks it as the most recently used.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.entry(slot).value)
    }

    /// Inserts or overwrites `key`, making it the most recently used.
    /// Evicts the least recently used entry if the cache would overflow.
    pub fn insert(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.entry_mut(slot).value = value;
            self.move_to_front(slot);
            return;
        }
        if self.index.len() >= self.capacity {
            self.evict();
        }
        let entry = Entry {
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

    /// Removes `key`, returning its value if it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> Option<V>
    where
        K: std::borrow::Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = self.index.remove(key)?;
        Some(self.release(slot).value)
    }

    fn evict(&mut self) {
        let slot = self.tail;
        if slot == NIL {
            return;
        }
        let entry = self.release(slot);
        self.index.remove(&entry.key);
    }

    /// Unlinks `slot`, frees it for reuse, and returns its entry.
    fn release(&mut self, slot: usize) -> Entry<K, V> {
        self.unlink(slot);
        self.free.push(slot);
        self.slots[slot].take().expect("released slot must be occupied")
    }

    fn entry(&self, slot: usize) -> &Entry<K, V> {
        self.slots[slot].as_ref().expect("linked slot must be occupied")
    }

    fn entry_mut(&mut self, slot: usize) -> &mut Entry<K, V> {
        self.slots[slot].as_mut().expect("linked slot must be occupied")
    }

    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        {
            let e = self.entry_mut(slot);
            e.prev = NIL;
            e.next = old_head;
        }
        if old_head != NIL {
            self.entry_mut(old_head).prev = slot;
        } else {
            self.tail = slot;
        }
        self.head = slot;
    }

    fn unlink(&mut self, slot: usize) {
        let (prev, next) = {
            let e = self.entry(slot);
            (e.prev, e.next)
        };
        if prev != NIL {
            self.entry_mut(prev).next = next;
        } else {
            self.head = next;
        }
        if next != NIL {
            self.entry_mut(next).prev = prev;
        } else {
            self.tail = prev;
        }
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
        let mut c = LruCache::new(2);
        c.insert("a", 1);
        c.insert("b", 2);
        assert_eq!(c.get("a"), Some(&1));
        c.insert("c", 3);
        assert_eq!(c.get("b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_and_remove_frees() {
        let mut c = LruCache::new(2);
        c.insert("a", 1);
        c.insert("b", 2);
        c.insert("a", 9);
        c.insert("c", 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
        assert_eq!(c.remove("a"), Some(9));
        assert_eq!(c.remove("a"), None);
        assert_eq!(c.len(), 1);
        c.insert("d", 4);
        c.insert("e", 5);
        assert_eq!(c.get("c"), None);
        assert_eq!(c.get("d"), Some(&4));
    }
}
