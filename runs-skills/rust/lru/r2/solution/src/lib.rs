//! A fixed-capacity least-recently-used cache and a driver for the `lru` command language.

use std::borrow::Borrow;
use std::collections::HashMap;
use std::hash::Hash;
use std::io::{self, Write};

const NIL: usize = usize::MAX;

#[derive(Debug)]
struct Node<K, V> {
    key: K,
    value: V,
    prev: usize,
    next: usize,
}

/// An LRU cache with O(1) expected-time `get`, `insert` and `remove`.
///
/// Entries live in a dense slab linked into a recency list (head = most recent);
/// a hash map maps each key to its slab slot.
#[derive(Debug)]
pub struct LruCache<K, V> {
    capacity: usize,
    map: HashMap<K, usize>,
    nodes: Vec<Node<K, V>>,
    head: usize,
    tail: usize,
}

impl<K: Hash + Eq + Clone, V> LruCache<K, V> {
    /// Creates an empty cache holding at most `capacity` entries.
    ///
    /// # Panics
    /// Panics if `capacity` is zero.
    #[must_use]
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
        Self {
            capacity,
            map: HashMap::new(),
            nodes: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of entries currently held.
    #[must_use]
    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    /// Returns `true` if the cache holds no entries.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get<Q>(&mut self, key: &Q) -> Option<&V>
    where
        K: Borrow<Q>,
        Q: Hash + Eq + ?Sized,
    {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(&self.nodes[idx].value)
    }

    /// Inserts or overwrites `key`, making it most recently used and evicting
    /// the least recently used entry if the capacity is exceeded.
    pub fn insert(&mut self, key: K, value: V) {
        if let Some(&idx) = self.map.get(&key) {
            self.nodes[idx].value = value;
            self.move_to_front(idx);
            return;
        }
        if self.nodes.len() == self.capacity {
            self.remove_at(self.tail);
        }
        let idx = self.nodes.len();
        self.map.insert(key.clone(), idx);
        self.nodes.push(Node {
            key,
            value,
            prev: NIL,
            next: NIL,
        });
        self.push_front(idx);
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

    fn unlink(&mut self, idx: usize) {
        let (prev, next) = (self.nodes[idx].prev, self.nodes[idx].next);
        match prev {
            NIL => self.head = next,
            p => self.nodes[p].next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.nodes[n].prev = prev,
        }
    }

    fn push_front(&mut self, idx: usize) {
        let old_head = self.head;
        self.nodes[idx].prev = NIL;
        self.nodes[idx].next = old_head;
        match old_head {
            NIL => self.tail = idx,
            h => self.nodes[h].prev = idx,
        }
        self.head = idx;
    }

    fn move_to_front(&mut self, idx: usize) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
        }
    }

    /// Removes the node in slot `idx`, keeping the slab dense by moving the
    /// last node into the vacated slot.
    fn remove_at(&mut self, idx: usize) -> V {
        self.unlink(idx);
        let node = self.nodes.swap_remove(idx);
        self.map.remove(&node.key);
        if idx < self.nodes.len() {
            // The former last node now lives at `idx`; repoint everything at it.
            let (prev, next) = (self.nodes[idx].prev, self.nodes[idx].next);
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
}

/// Error produced when the input cannot be interpreted.
#[derive(Debug)]
pub enum Error {
    /// The first line is not an integer in `1..=1_000_000`.
    InvalidCapacity,
    /// Writing output failed.
    Io(io::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidCapacity => f.write_str("first line must be a capacity in 1..=1000000"),
            Self::Io(e) => write!(f, "I/O error: {e}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(e) => Some(e),
            Self::InvalidCapacity => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

const MAX_CAPACITY: usize = 1_000_000;

/// Executes the command script in `input`, writing results to `out`.
///
/// Blank or unrecognised lines are ignored.
///
/// # Errors
/// Returns [`Error::InvalidCapacity`] for a bad first line and [`Error::Io`] if writing fails.
pub fn run(input: &[u8], out: &mut impl Write) -> Result<(), Error> {
    let mut lines = input
        .split(|&b| b == b'\n')
        .map(|l| l.strip_suffix(b"\r").unwrap_or(l));

    let capacity = lines
        .next()
        .and_then(|l| std::str::from_utf8(l).ok())
        .and_then(|s| s.trim().parse::<usize>().ok())
        .filter(|c| (1..=MAX_CAPACITY).contains(c))
        .ok_or(Error::InvalidCapacity)?;

    let mut cache: LruCache<Box<[u8]>, Box<[u8]>> = LruCache::new(capacity);

    for line in lines {
        let mut parts = line.split(|&b| b == b' ');
        match (parts.next(), parts.next(), parts.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.insert(key.into(), value.into()),
            (Some(b"GET"), Some(key), _) => match cache.get(key) {
                Some(value) => {
                    out.write_all(value)?;
                    out.write_all(b"\n")?;
                }
                None => out.write_all(b"NULL\n")?,
            },
            (Some(b"DEL"), Some(key), _) => {
                let hit = cache.remove(key).is_some();
                out.write_all(if hit { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), _, _) => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn exec(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).expect("run failed");
        String::from_utf8(out).expect("utf8")
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            exec("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n"),
            "1\nNULL\n2\n"
        );
    }

    #[test]
    fn overwrite_refreshes_and_no_trailing_newline() {
        assert_eq!(
            exec("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c"),
            "9\nNULL\n3\n"
        );
    }

    #[test]
    fn delete_compacts_slab() {
        let mut c = LruCache::new(3);
        c.insert(1, 'a');
        c.insert(2, 'b');
        c.insert(3, 'c');
        assert_eq!(c.remove(&1), Some('a'));
        assert_eq!(c.remove(&1), None);
        c.insert(4, 'd');
        c.insert(5, 'e'); // evicts 2
        assert_eq!(c.get(&2), None);
        assert_eq!(c.get(&3), Some(&'c'));
        c.insert(6, 'f'); // evicts 4
        assert_eq!(c.get(&4), None);
        assert_eq!(c.len(), 3);
        for k in [3, 5, 6] {
            assert!(c.remove(&k).is_some());
        }
        assert!(c.is_empty());
    }

    #[test]
    fn rejects_bad_capacity() {
        assert!(matches!(
            run(b"0\n", &mut Vec::new()),
            Err(Error::InvalidCapacity)
        ));
    }
}
