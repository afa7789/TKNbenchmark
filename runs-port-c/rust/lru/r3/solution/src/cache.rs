//! A fixed-capacity LRU cache with O(1) expected time per operation.
//!
//! Entries live in a slab of nodes linked into an intrusive doubly linked
//! recency list; a hash map indexes the slab by key. Keys and values are
//! borrowed slices, so the cache never copies the data it stores.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node<'a> {
    key: &'a [u8],
    value: &'a [u8],
    /// Towards the more recently used end.
    prev: usize,
    /// Towards the less recently used end.
    next: usize,
}

/// 64-bit FNV-1a: fast for the short keys this cache stores.
#[derive(Debug)]
pub struct FnvHasher(u64);

impl Default for FnvHasher {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for FnvHasher {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn finish(&self) -> u64 {
        self.0 ^ (self.0 >> 29)
    }
}

type FnvBuildHasher = BuildHasherDefault<FnvHasher>;

#[derive(Debug)]
pub struct LruCache<'a> {
    index: HashMap<&'a [u8], usize, FnvBuildHasher>,
    nodes: Vec<Node<'a>>,
    free: Vec<usize>,
    /// Most recently used node.
    head: usize,
    /// Least recently used node.
    tail: usize,
    capacity: usize,
}

impl<'a> LruCache<'a> {
    /// Creates an empty cache holding at most `capacity` keys (minimum 1).
    ///
    /// `expected` is a hint for how many entries to preallocate.
    pub fn with_capacity(capacity: usize, expected: usize) -> Self {
        let capacity = capacity.max(1);
        let reserve = expected.min(capacity);
        Self {
            index: HashMap::with_capacity_and_hasher(reserve, FnvBuildHasher::default()),
            nodes: Vec::with_capacity(reserve),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
            capacity,
        }
    }

    /// Number of keys currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get(&mut self, key: &[u8]) -> Option<&'a [u8]> {
        let i = *self.index.get(key)?;
        self.touch(i);
        Some(self.nodes[i].value)
    }

    /// Inserts or overwrites `key`, making it most recently used and
    /// evicting the least recently used key if the cache overflows.
    pub fn set(&mut self, key: &'a [u8], value: &'a [u8]) {
        if let Some(&i) = self.index.get(key) {
            self.nodes[i].value = value;
            self.touch(i);
            return;
        }

        if self.len() == self.capacity {
            self.evict_lru();
        }

        let node = Node { key, value, prev: NIL, next: NIL };
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
        self.index.insert(key, i);
        self.push_front(i);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.remove(key) {
            Some(i) => {
                self.release(i);
                true
            }
            None => false,
        }
    }

    fn evict_lru(&mut self) {
        let i = self.tail;
        if i != NIL {
            self.index.remove(self.nodes[i].key);
            self.release(i);
        }
    }

    /// Unlinks node `i` and returns its slot to the free list.
    fn release(&mut self, i: usize) {
        self.unlink(i);
        self.free.push(i);
    }

    fn touch(&mut self, i: usize) {
        if self.head != i {
            self.unlink(i);
            self.push_front(i);
        }
    }

    fn unlink(&mut self, i: usize) {
        let Node { prev, next, .. } = self.nodes[i];
        match prev {
            NIL => self.head = next,
            p => self.nodes[p].next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.nodes[n].prev = prev,
        }
    }

    fn push_front(&mut self, i: usize) {
        let old_head = self.head;
        let node = &mut self.nodes[i];
        node.prev = NIL;
        node.next = old_head;
        match old_head {
            NIL => self.tail = i,
            h => self.nodes[h].prev = i,
        }
        self.head = i;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evicts_least_recently_used() {
        let mut c = LruCache::with_capacity(2, 0);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        assert_eq!(c.get(b"a"), Some(&b"1"[..]));
        c.set(b"c", b"3");
        assert_eq!(c.get(b"b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let mut c = LruCache::with_capacity(2, 0);
        c.set(b"a", b"1");
        c.set(b"b", b"2");
        c.set(b"a", b"9");
        c.set(b"c", b"3");
        assert_eq!(c.get(b"a"), Some(&b"9"[..]));
        assert_eq!(c.get(b"b"), None);
    }

    #[test]
    fn remove_reports_presence_and_reuses_slots() {
        let mut c = LruCache::with_capacity(3, 0);
        c.set(b"x", b"1");
        assert!(c.remove(b"x"));
        assert!(!c.remove(b"x"));
        assert_eq!(c.len(), 0);
        c.set(b"y", b"2");
        assert_eq!(c.nodes.len(), 1);
        assert_eq!(c.get(b"y"), Some(&b"2"[..]));
    }
}
