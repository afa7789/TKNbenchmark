//! An LRU cache simulator driven by a simple line-oriented command language.
//!
//! The cache borrows keys and values directly from the input buffer, so
//! processing a command never allocates beyond the cache's own bookkeeping.

use std::collections::HashMap;
use std::io::{self, Write};

/// Sentinel index meaning "no node".
const NIL: u32 = u32::MAX;

#[derive(Debug, Clone, Copy)]
struct Node<'a> {
    key: &'a [u8],
    value: &'a [u8],
    prev: u32,
    next: u32,
}

/// A fixed-capacity least-recently-used cache with O(1) expected-time operations.
///
/// Entries live in a slab (`nodes`) linked into a doubly linked recency list;
/// `head` is the most recently used entry and `tail` the least.
#[derive(Debug)]
pub struct LruCache<'a> {
    capacity: usize,
    map: HashMap<&'a [u8], u32>,
    nodes: Vec<Node<'a>>,
    free: Vec<u32>,
    head: u32,
    tail: u32,
}

impl<'a> LruCache<'a> {
    /// Creates an empty cache holding at most `capacity` keys.
    ///
    /// # Panics
    ///
    /// Panics if `capacity` is zero or does not fit the internal `u32` indices.
    #[must_use]
    pub fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "capacity must be positive");
        assert!(capacity < NIL as usize, "capacity too large");
        Self {
            capacity,
            map: HashMap::new(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of keys currently held.
    #[must_use]
    pub fn len(&self) -> usize {
        self.map.len()
    }

    /// Whether the cache holds no keys.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get(&mut self, key: &[u8]) -> Option<&'a [u8]> {
        let idx = *self.map.get(key)?;
        self.move_to_front(idx);
        Some(self.node(idx).value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting
    /// the least recently used key if the capacity is exceeded.
    pub fn set(&mut self, key: &'a [u8], value: &'a [u8]) {
        if let Some(&idx) = self.map.get(key) {
            self.node_mut(idx).value = value;
            self.move_to_front(idx);
            return;
        }

        let node = Node {
            key,
            value,
            prev: NIL,
            next: NIL,
        };
        let idx = if self.map.len() >= self.capacity {
            // Reuse the evicted tail's slot for the new entry.
            let victim = self.tail;
            self.unlink(victim);
            self.map.remove(self.node(victim).key);
            *self.node_mut(victim) = node;
            victim
        } else if let Some(idx) = self.free.pop() {
            *self.node_mut(idx) = node;
            idx
        } else {
            #[expect(
                clippy::cast_possible_truncation,
                reason = "the slab never exceeds `capacity`, which `new` keeps below u32::MAX"
            )]
            let idx = self.nodes.len() as u32;
            self.nodes.push(node);
            idx
        };
        self.push_front(idx);
        self.map.insert(key, idx);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        let Some(idx) = self.map.remove(key) else {
            return false;
        };
        self.unlink(idx);
        self.free.push(idx);
        true
    }

    fn node(&self, idx: u32) -> &Node<'a> {
        &self.nodes[idx as usize]
    }

    fn node_mut(&mut self, idx: u32) -> &mut Node<'a> {
        &mut self.nodes[idx as usize]
    }

    fn unlink(&mut self, idx: u32) {
        let Node { prev, next, .. } = *self.node(idx);
        if prev == NIL {
            self.head = next;
        } else {
            self.node_mut(prev).next = next;
        }
        if next == NIL {
            self.tail = prev;
        } else {
            self.node_mut(next).prev = prev;
        }
    }

    fn push_front(&mut self, idx: u32) {
        let old_head = self.head;
        let node = self.node_mut(idx);
        node.prev = NIL;
        node.next = old_head;
        if old_head == NIL {
            self.tail = idx;
        } else {
            self.node_mut(old_head).prev = idx;
        }
        self.head = idx;
    }

    fn move_to_front(&mut self, idx: u32) {
        if self.head != idx {
            self.unlink(idx);
            self.push_front(idx);
        }
    }
}

/// Error produced when the input cannot be processed.
#[derive(Debug)]
pub enum Error {
    /// The first line is missing or is not a valid capacity.
    InvalidCapacity,
    /// Writing output failed.
    Io(io::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidCapacity => {
                f.write_str("first line must be a capacity between 1 and 1000000")
            }
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

fn parse_capacity(line: &[u8]) -> Result<usize, Error> {
    let text = std::str::from_utf8(line).map_err(|_| Error::InvalidCapacity)?;
    match text.trim().parse::<usize>() {
        Ok(c) if (1..=1_000_000).contains(&c) => Ok(c),
        _ => Err(Error::InvalidCapacity),
    }
}

/// Runs the command script in `input`, writing results to `out`.
///
/// Blank lines and unrecognised or malformed commands are ignored.
///
/// # Errors
///
/// Returns [`Error::InvalidCapacity`] if the first line is not a valid
/// capacity, or [`Error::Io`] if writing fails.
pub fn run(input: &[u8], out: &mut impl Write) -> Result<(), Error> {
    let mut lines = input
        .split(|&b| b == b'\n')
        .map(|line| line.strip_suffix(b"\r").unwrap_or(line));
    let capacity = parse_capacity(lines.next().unwrap_or_default())?;
    let mut cache = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        match (tokens.next(), tokens.next(), tokens.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.set(key, value),
            (Some(b"GET"), Some(key), None) => {
                out.write_all(cache.get(key).unwrap_or(b"NULL"))?;
                out.write_all(b"\n")?;
            }
            (Some(b"DEL"), Some(key), None) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), None, None) => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    out.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn exec(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).expect("run succeeds");
        String::from_utf8(out).expect("utf-8 output")
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            exec("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n"),
            "1\nNULL\n2\n"
        );
    }

    #[test]
    fn overwrite_refreshes_recency() {
        assert_eq!(
            exec("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c"),
            "9\nNULL\n3\n"
        );
    }

    #[test]
    fn delete_then_reuse_slot() {
        assert_eq!(
            exec("2\nSET a 1\nSET b 2\nDEL a\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE"),
            "1\n0\nNULL\n3\n4\n2\n"
        );
    }

    #[test]
    fn capacity_one() {
        assert_eq!(
            exec("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n"),
            "NULL\n2\n1\n"
        );
    }

    #[test]
    fn delete_everything() {
        assert_eq!(
            exec("3\nSET a 1\nSET b 2\nDEL b\nDEL a\nSIZE\nSET c 3\nGET c\n"),
            "1\n1\n0\n3\n"
        );
    }

    #[test]
    fn rejects_bad_capacity() {
        let mut out = Vec::new();
        assert!(matches!(run(b"0\n", &mut out), Err(Error::InvalidCapacity)));
    }
}
