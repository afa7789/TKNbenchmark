//! Fixed-capacity LRU cache keyed by byte strings.
//!
//! Keys and values are borrowed slices, so the cache never copies them; the
//! backing storage only has to outlive the cache. Entries live in a pool and
//! refer to each other by index, forming an intrusive doubly linked recency
//! list. All operations run in O(1) expected time.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

/// FNV-1a with a splitmix64 finalizer: fast for the short keys we expect and
/// well mixed in every bit, which hashbrown relies on.
struct KeyHasher(u64);

impl Default for KeyHasher {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for KeyHasher {
    fn write(&mut self, bytes: &[u8]) {
        let mut h = self.0;
        for &b in bytes {
            h ^= u64::from(b);
            h = h.wrapping_mul(0x0100_0000_01b3);
        }
        self.0 = h;
    }

    fn finish(&self) -> u64 {
        let mut h = self.0;
        h ^= h >> 30;
        h = h.wrapping_mul(0xbf58_476d_1ce4_e5b9);
        h ^= h >> 27;
        h = h.wrapping_mul(0x94d0_49bb_1331_11eb);
        h ^ (h >> 31)
    }
}

type KeyMap<'a> = HashMap<&'a [u8], usize, BuildHasherDefault<KeyHasher>>;

/// Index of the sentinel node that anchors the recency list.
const HEAD: usize = 0;

#[derive(Clone, Copy)]
struct Node<'a> {
    key: &'a [u8],
    value: &'a [u8],
    /// Towards the most recently used entry.
    prev: usize,
    /// Towards the least recently used entry.
    next: usize,
}

pub struct LruCache<'a> {
    map: KeyMap<'a>,
    /// `nodes[HEAD]` is the sentinel; `HEAD.next` is the most recently used
    /// entry and `HEAD.prev` the least recently used one.
    nodes: Vec<Node<'a>>,
    /// Indices of nodes released by `remove` and available for reuse.
    free: Vec<usize>,
    capacity: usize,
}

impl<'a> LruCache<'a> {
    /// Creates a cache holding at most `capacity` keys (`capacity >= 1`).
    ///
    /// `expected_entries` bounds how many keys are likely to be live at once;
    /// storage is preallocated for `min(capacity, expected_entries)` entries.
    pub fn new(capacity: usize, expected_entries: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
        let live = capacity.min(expected_entries).max(1);
        let sentinel = Node {
            key: &[],
            value: &[],
            prev: HEAD,
            next: HEAD,
        };
        let mut nodes = Vec::with_capacity(live + 1);
        nodes.push(sentinel);
        Self {
            map: KeyMap::with_capacity_and_hasher(live, Default::default()),
            nodes,
            free: Vec::new(),
            capacity,
        }
    }

    /// Number of keys currently held.
    pub fn len(&self) -> usize {
        self.map.len()
    }

    /// Inserts or overwrites `key`, making it the most recently used entry
    /// and evicting the least recently used one if the cache overflows.
    pub fn set(&mut self, key: &'a [u8], value: &'a [u8]) {
        if let Some(&i) = self.map.get(key) {
            self.nodes[i].value = value;
            self.touch(i);
            return;
        }

        // Evicting before inserting is observably identical to inserting and
        // then evicting, and keeps the pool bounded by the capacity.
        if self.map.len() >= self.capacity {
            let lru = self.nodes[HEAD].prev;
            self.map.remove(self.nodes[lru].key);
            self.release(lru);
        }

        let node = Node {
            key,
            value,
            prev: HEAD,
            next: HEAD,
        };
        let i = match self.free.pop() {
            Some(i) => {
                self.nodes[i] = node;
                i
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.push_front(i);
        self.map.insert(key, i);
    }

    /// Looks up `key`; on a hit it becomes the most recently used entry.
    pub fn get(&mut self, key: &[u8]) -> Option<&'a [u8]> {
        let i = *self.map.get(key)?;
        self.touch(i);
        Some(self.nodes[i].value)
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.map.remove(key) {
            Some(i) => {
                self.release(i);
                true
            }
            None => false,
        }
    }

    /// Moves node `i` to the front of the recency list.
    fn touch(&mut self, i: usize) {
        if self.nodes[HEAD].next != i {
            self.unlink(i);
            self.push_front(i);
        }
    }

    /// Unlinks node `i` from the recency list and returns it to the pool.
    fn release(&mut self, i: usize) {
        self.unlink(i);
        self.free.push(i);
    }

    fn unlink(&mut self, i: usize) {
        let Node { prev, next, .. } = self.nodes[i];
        self.nodes[prev].next = next;
        self.nodes[next].prev = prev;
    }

    fn push_front(&mut self, i: usize) {
        let first = self.nodes[HEAD].next;
        self.nodes[i].prev = HEAD;
        self.nodes[i].next = first;
        self.nodes[first].prev = i;
        self.nodes[HEAD].next = i;
    }
}

#[cfg(test)]
mod tests {
    use super::LruCache;

    #[test]
    fn evicts_least_recently_used() {
        let mut c = LruCache::new(2, 10);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        assert_eq!(c.get(b"a"), Some(&b"1"[..]));
        c.set(b"c", b"3");
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut c = LruCache::new(2, 10);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        c.set(b"a", b"9");
        c.set(b"c", b"3");
        assert_eq!(c.get(b"a"), Some(&b"9"[..]));
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.get(b"c"), Some(&b"3"[..]));
    }

    #[test]
    fn remove_and_reuse() {
        let mut c = LruCache::new(1, 1);
        c.set(b"x", b"1");
        assert!(c.remove(b"x"));
        assert!(!c.remove(b"x"));
        assert_eq!(c.len(), 0);
        c.set(b"y", b"2");
        c.set(b"z", b"3");
        assert_eq!(c.get(b"y"), None);
        assert_eq!(c.get(b"z"), Some(&b"3"[..]));
        assert_eq!(c.len(), 1);
    }
}
