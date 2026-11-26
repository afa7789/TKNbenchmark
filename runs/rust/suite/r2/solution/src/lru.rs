//! LRU cache simulator.
//!
//! The first input line holds the capacity; every later line is a `SET`, `GET`, `DEL` or `SIZE`
//! command. Entries live in a slab threaded by an intrusive doubly linked list (most recently used
//! at the head), indexed by a hash map from key to slab slot, so every command is O(1) expected.

use std::collections::HashMap;
use std::io::{self, Write};

/// Runs the commands in `input` and writes one line per `GET`, `DEL` and `SIZE`.
pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n').map(trim_cr);
    let capacity = lines
        .next()
        .and_then(|line| std::str::from_utf8(line).ok())
        .and_then(|s| s.trim().parse::<usize>().ok())
        .filter(|&c| c >= 1)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "lru: invalid capacity line"))?;

    let mut cache = LruCache::new(capacity);
    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        match (tokens.next(), tokens.next(), tokens.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.set(key, value),
            (Some(b"GET"), Some(key), _) => match cache.get(key) {
                Some(value) => {
                    out.write_all(value)?;
                    out.write_all(b"\n")?;
                }
                None => out.write_all(b"NULL\n")?,
            },
            (Some(b"DEL"), Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), _, _) => writeln!(out, "{}", cache.len())?,
            // Blank or malformed lines are not commands; they produce no output.
            _ => {}
        }
    }
    Ok(())
}

fn trim_cr(line: &[u8]) -> &[u8] {
    line.strip_suffix(b"\r").unwrap_or(line)
}

/// Slab index meaning "no node".
const NIL: usize = usize::MAX;

struct Node {
    key: Box<[u8]>,
    value: Vec<u8>,
    prev: usize,
    next: usize,
}

/// A fixed-capacity map that evicts its least recently used entry when full.
pub struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    free: Vec<usize>,
    head: usize,
    tail: usize,
}

impl LruCache {
    /// Creates an empty cache holding at most `capacity` keys (`capacity` ≥ 1).
    pub fn new(capacity: usize) -> Self {
        assert!(capacity >= 1, "LRU capacity must be at least 1");
        Self {
            capacity,
            index: HashMap::new(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    /// Number of keys currently held.
    pub fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns the value for `key`, marking it most recently used.
    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.nodes[slot].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting if over capacity.
    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&slot) = self.index.get(key) {
            let node = &mut self.nodes[slot];
            node.value.clear();
            node.value.extend_from_slice(value);
            self.move_to_front(slot);
            return;
        }

        let node = Node {
            key: key.into(),
            value: value.to_vec(),
            prev: NIL,
            next: NIL,
        };
        let slot = match self.free.pop() {
            Some(slot) => {
                self.nodes[slot] = node;
                slot
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.index.insert(key.into(), slot);
        self.push_front(slot);

        if self.index.len() > self.capacity {
            let lru = self.tail;
            self.evict(lru);
        }
    }

    /// Removes `key`, reporting whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.get(key) {
            Some(&slot) => {
                self.evict(slot);
                true
            }
            None => false,
        }
    }

    fn evict(&mut self, slot: usize) {
        self.unlink(slot);
        let node = &mut self.nodes[slot];
        self.index.remove(&node.key);
        node.key = Box::default();
        node.value = Vec::new();
        self.free.push(slot);
    }

    fn move_to_front(&mut self, slot: usize) {
        if self.head != slot {
            self.unlink(slot);
            self.push_front(slot);
        }
    }

    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        let node = &mut self.nodes[slot];
        node.prev = NIL;
        node.next = old_head;
        match old_head {
            NIL => self.tail = slot,
            h => self.nodes[h].prev = slot,
        }
        self.head = slot;
    }

    fn unlink(&mut self, slot: usize) {
        let Node { prev, next, .. } = self.nodes[slot];
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
    use super::*;

    fn render(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        assert_eq!(render("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n"), "1\nNULL\n2\n");
    }

    #[test]
    fn overwrite_refreshes_recency() {
        assert_eq!(render("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c"), "9\nNULL\n3\n");
    }

    #[test]
    fn delete_and_reuse_slots() {
        assert_eq!(
            render("2\nSET x 1\nDEL x\nDEL x\nSIZE\nSET y 2\nSET z 3\nSET w 4\nGET y\nGET z\nGET w\nSIZE"),
            "1\n0\n0\nNULL\n3\n4\n2\n"
        );
    }

    #[test]
    fn capacity_one() {
        assert_eq!(render("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n"), "NULL\n2\n1\n");
    }
}
