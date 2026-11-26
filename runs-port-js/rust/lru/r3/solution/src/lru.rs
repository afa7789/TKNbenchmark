//! Fixed-capacity LRU cache backed by a hash map and an intrusive doubly
//! linked list stored in a slab of nodes. Every operation is O(1) expected.

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
    /// Most recently used.
    head: usize,
    /// Least recently used.
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache. A capacity of zero is treated as one.
    pub fn new(capacity: usize) -> Self {
        let capacity = capacity.max(1);
        // Reserve up front, but bound it so a huge capacity with few
        // commands does not allocate eagerly.
        let reserve = capacity.saturating_add(1).min(1 << 16);
        Self {
            capacity,
            index: HashMap::with_capacity(reserve),
            nodes: Vec::with_capacity(reserve),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of entries currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.node(slot).value)
    }

    /// Inserts or overwrites `key`, making it most recently used and
    /// evicting the least recently used entry if capacity is exceeded.
    pub fn set(&mut self, key: K, value: V) {
        if let Some(&slot) = self.index.get(&key) {
            self.node_mut(slot).value = value;
            self.move_to_front(slot);
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
            self.remove_slot(self.tail);
        }
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove<Q>(&mut self, key: &Q) -> bool
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        match self.index.get(key) {
            Some(&slot) => {
                self.remove_slot(slot);
                true
            }
            None => false,
        }
    }

    fn node(&self, slot: usize) -> &Node<K, V> {
        self.nodes[slot].as_ref().expect("slot is live")
    }

    fn node_mut(&mut self, slot: usize) -> &mut Node<K, V> {
        self.nodes[slot].as_mut().expect("slot is live")
    }

    fn remove_slot(&mut self, slot: usize) {
        self.unlink(slot);
        let node = self.nodes[slot].take().expect("slot is live");
        self.index.remove(&node.key);
        self.free.push(slot);
    }

    fn push_front(&mut self, slot: usize) {
        let head = self.head;
        {
            let node = self.node_mut(slot);
            node.prev = NIL;
            node.next = head;
        }
        if head != NIL {
            self.node_mut(head).prev = slot;
        } else {
            self.tail = slot;
        }
        self.head = slot;
    }

    fn unlink(&mut self, slot: usize) {
        let (prev, next) = {
            let node = self.node(slot);
            (node.prev, node.next)
        };
        if prev != NIL {
            self.node_mut(prev).next = next;
        } else {
            self.head = next;
        }
        if next != NIL {
            self.node_mut(next).prev = prev;
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
        c.set("a", 1);
        c.set("b", 2);
        assert_eq!(c.get("a"), Some(&1));
        c.set("c", 3);
        assert_eq!(c.get("b"), None);
        assert_eq!(c.len(), 2);
    }

    #[test]
    fn overwrite_refreshes_and_remove_works() {
        let mut c = LruCache::new(2);
        c.set("a", 1);
        c.set("b", 2);
        c.set("a", 9);
        c.set("c", 3);
        assert_eq!(c.get("a"), Some(&9));
        assert_eq!(c.get("b"), None);
        assert!(c.remove("a"));
        assert!(!c.remove("a"));
        assert_eq!(c.len(), 1);
    }
}
