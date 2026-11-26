//! `app lru`: LRU cache simulator. See the `lru` section of SPEC.md.
//!
//! The cache is a hash map from key to slot index plus an intrusive doubly
//! linked recency list stored in a slab (`Vec<Node>`), so every command runs
//! in O(1) expected time without per-node heap links. Keys and values are
//! handled as raw bytes: the spec restricts them to printable ASCII, so no
//! UTF-8 validation is needed.

use std::collections::HashMap;
use std::io::{self, BufRead, Write};

/// Largest capacity the spec allows; also bounds up-front allocation.
const MAX_CAPACITY: usize = 1_000_000;

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

/// Entry point for `app lru`: reads `input` to completion and writes the
/// result to `output`. The caller flushes `output`.
pub fn run<R: BufRead, W: Write>(mut input: R, mut output: W) -> io::Result<()> {
    let mut line = Vec::with_capacity(256);

    // Line 1: capacity. Empty input means there is nothing to simulate.
    if input.read_until(b'\n', &mut line)? == 0 {
        return Ok(());
    }
    let capacity = parse_capacity(trim_line(&line))?;
    let mut cache = LruCache::new(capacity);

    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            break;
        }
        execute(&mut cache, trim_line(&line), &mut output)?;
    }
    Ok(())
}

/// Runs one command line against `cache`, writing any output it produces.
/// Lines that are not a well-formed command are ignored.
fn execute<W: Write>(cache: &mut LruCache, line: &[u8], output: &mut W) -> io::Result<()> {
    let mut tokens = line.split(|&b| b == b' ');
    let command = tokens.next().unwrap_or_default();
    let args = (tokens.next(), tokens.next(), tokens.next());

    match (command, args) {
        (b"SET", (Some(key), Some(value), None)) => cache.set(key, value),
        (b"GET", (Some(key), None, None)) => {
            let value = cache.get(key).unwrap_or(b"NULL");
            output.write_all(value)?;
            output.write_all(b"\n")?;
        }
        (b"DEL", (Some(key), None, None)) => {
            output.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
        }
        (b"SIZE", (None, None, None)) => writeln!(output, "{}", cache.len())?,
        _ => {}
    }
    Ok(())
}

/// Strips the line terminator (`\n`, tolerating a preceding `\r`).
fn trim_line(line: &[u8]) -> &[u8] {
    let line = line.strip_suffix(b"\n").unwrap_or(line);
    line.strip_suffix(b"\r").unwrap_or(line)
}

fn parse_capacity(line: &[u8]) -> io::Result<usize> {
    std::str::from_utf8(line)
        .ok()
        .and_then(|s| s.trim().parse::<usize>().ok())
        .filter(|c| (1..=MAX_CAPACITY).contains(c))
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("lru: invalid capacity {:?}", String::from_utf8_lossy(line)),
            )
        })
}

/// A slot in the recency list.
struct Node {
    key: Box<[u8]>,
    value: Box<[u8]>,
    prev: usize,
    next: usize,
}

/// A fixed-capacity least-recently-used cache over byte-string keys and values.
struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    /// Slots of removed nodes, reused before the slab grows.
    free: Vec<usize>,
    /// Most recently used node.
    head: usize,
    /// Least recently used node.
    tail: usize,
}

impl LruCache {
    fn new(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
        Self {
            capacity,
            index: HashMap::with_capacity(capacity + 1),
            nodes: Vec::with_capacity(capacity),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns the value for `key`, marking it most recently used on a hit.
    fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.nodes[slot].value)
    }

    /// Inserts or overwrites `key`, making it most recently used and evicting
    /// the least recently used entry if the cache would exceed its capacity.
    fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&slot) = self.index.get(key) {
            let node = &mut self.nodes[slot];
            if *node.value != *value {
                node.value = value.into();
            }
            self.move_to_front(slot);
            return;
        }

        if self.len() == self.capacity {
            // Recycle the evicted node's slot and key allocation in place.
            let slot = self.tail;
            self.unlink(slot);
            let node = &mut self.nodes[slot];
            self.index.remove(&node.key);
            node.key = key.into();
            node.value = value.into();
            self.index.insert(node.key.clone(), slot);
            self.push_front(slot);
            return;
        }

        let node = Node {
            key: key.into(),
            value: value.into(),
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
    }

    /// Removes `key`, returning whether it was present.
    fn remove(&mut self, key: &[u8]) -> bool {
        let Some(slot) = self.index.remove(key) else {
            return false;
        };
        self.unlink(slot);
        let node = &mut self.nodes[slot];
        node.key = Box::default();
        node.value = Box::default();
        self.free.push(slot);
        true
    }

    fn move_to_front(&mut self, slot: usize) {
        if self.head != slot {
            self.unlink(slot);
            self.push_front(slot);
        }
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

    fn push_front(&mut self, slot: usize) {
        let old_head = self.head;
        {
            let node = &mut self.nodes[slot];
            node.prev = NIL;
            node.next = old_head;
        }
        match old_head {
            NIL => self.tail = slot,
            h => self.nodes[h].prev = slot,
        }
        self.head = slot;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn simulate(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(simulate(input), "1\nNULL\n2\n");
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let input = "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c";
        assert_eq!(simulate(input), "9\nNULL\n3\n");
    }

    #[test]
    fn delete_then_reuse_slots() {
        let input = "2\nSET a 1\nSET b 2\nDEL a\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n";
        assert_eq!(simulate(input), "1\n0\nNULL\n3\n4\n2\n");
    }

    #[test]
    fn capacity_one() {
        let input = "1\nSET a 1\nSET b 2\nGET a\nGET b\nDEL b\nSIZE\nSET c 3\nGET c\n";
        assert_eq!(simulate(input), "NULL\n2\n1\n0\n3\n");
    }

    #[test]
    fn empty_input_prints_nothing() {
        assert_eq!(simulate(""), "");
        assert_eq!(simulate("5\n"), "");
    }
}
