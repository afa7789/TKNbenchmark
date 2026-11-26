//! `app lru`: LRU cache simulator: executes SET/GET/DEL/SIZE commands against a bounded cache.
//!
//! See the `lru` section of SPEC.md.
//!
//! The cache is a hash map from key to a slot in an arena of nodes; the nodes form an
//! intrusive doubly linked list ordered from most to least recently used. Every command is
//! O(1) expected time, and freed slots are recycled so the arena never exceeds `C + 1` nodes.

use std::collections::HashMap;
use std::io::{self, BufRead, Write};

/// Largest capacity accepted on the first line.
const MAX_CAPACITY: usize = 1_000_000;

/// Entry point for `app lru`: reads all of `input` and writes the result to `output`.
///
/// `output` is already buffered and is flushed by the caller.
///
/// Blank lines and lines that are not a well-formed command are ignored.
pub fn run(mut input: impl BufRead, mut output: impl Write) -> io::Result<()> {
    let mut line = Vec::new();
    if input.read_until(b'\n', &mut line)? == 0 {
        return Ok(());
    }
    let capacity = parse_capacity(trim_line_end(&line))?;
    let mut cache = LruCache::with_capacity(capacity);

    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            return Ok(());
        }
        let Some(command) = Command::parse(trim_line_end(&line)) else {
            continue;
        };
        match command {
            Command::Set { key, value } => cache.set(key, value),
            Command::Get { key } => {
                let value = cache.get(key).unwrap_or(b"NULL");
                output.write_all(value)?;
                output.write_all(b"\n")?;
            }
            Command::Del { key } => {
                output.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            Command::Size => writeln!(output, "{}", cache.len())?,
        }
    }
}

/// Strips the line terminator (`\n`, tolerating a preceding `\r`).
fn trim_line_end(line: &[u8]) -> &[u8] {
    let line = line.strip_suffix(b"\n").unwrap_or(line);
    line.strip_suffix(b"\r").unwrap_or(line)
}

fn parse_capacity(line: &[u8]) -> io::Result<usize> {
    std::str::from_utf8(line)
        .ok()
        .and_then(|text| text.trim().parse::<usize>().ok())
        .filter(|capacity| (1..=MAX_CAPACITY).contains(capacity))
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "invalid capacity '{}': expected an integer in 1..={MAX_CAPACITY}",
                    String::from_utf8_lossy(line)
                ),
            )
        })
}

/// One parsed input line, borrowing its tokens from the line buffer.
#[derive(Debug, PartialEq, Eq)]
enum Command<'a> {
    Set { key: &'a [u8], value: &'a [u8] },
    Get { key: &'a [u8] },
    Del { key: &'a [u8] },
    Size,
}

impl<'a> Command<'a> {
    /// Parses a line without its terminator; returns `None` if it is not a valid command.
    fn parse(line: &'a [u8]) -> Option<Self> {
        let mut tokens = line.split(|&byte| byte == b' ');
        let name = tokens.next()?;
        let mut operand = || tokens.next().filter(|token| !token.is_empty());
        let command = match name {
            b"SET" => Command::Set {
                key: operand()?,
                value: operand()?,
            },
            b"GET" => Command::Get { key: operand()? },
            b"DEL" => Command::Del { key: operand()? },
            b"SIZE" => Command::Size,
            _ => return None,
        };
        // Trailing tokens make the line malformed.
        tokens.next().is_none().then_some(command)
    }
}

/// Index of a node in the arena.
type Slot = u32;

/// Sentinel link meaning "no node".
const NIL: Slot = Slot::MAX;

#[derive(Debug)]
struct Node {
    key: Box<[u8]>,
    value: Vec<u8>,
    /// Neighbour towards the most recently used end.
    prev: Slot,
    /// Neighbour towards the least recently used end.
    next: Slot,
}

/// A fixed-capacity map that evicts its least recently used key on overflow.
#[derive(Debug)]
struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, Slot>,
    nodes: Vec<Node>,
    /// Slots of removed nodes, available for reuse.
    free: Vec<Slot>,
    /// Most recently used node.
    head: Slot,
    /// Least recently used node.
    tail: Slot,
}

impl LruCache {
    /// Creates an empty cache holding at most `capacity` keys.
    ///
    /// # Panics
    ///
    /// If `capacity` is zero or too large for the slot type.
    fn with_capacity(capacity: usize) -> Self {
        assert!(capacity > 0, "LRU capacity must be positive");
        assert!(
            capacity < NIL as usize,
            "LRU capacity {capacity} exceeds the slot range"
        );
        // Reserve lazily-bounded space: large capacities are often never filled.
        let initial = capacity.min(1 << 16) + 1;
        Self {
            capacity,
            index: HashMap::with_capacity(initial),
            nodes: Vec::with_capacity(initial),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    fn len(&self) -> usize {
        self.index.len()
    }

    /// Returns the value for `key`, marking it most recently used.
    fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let slot = *self.index.get(key)?;
        self.move_to_front(slot);
        Some(&self.node(slot).value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting the least
    /// recently used key if the cache overflows.
    fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&slot) = self.index.get(key) {
            let node = self.node_mut(slot);
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
                *self.node_mut(slot) = node;
                slot
            }
            None => {
                let slot = Slot::try_from(self.nodes.len()).expect("arena exceeds slot range");
                self.nodes.push(node);
                slot
            }
        };
        self.index.insert(key.into(), slot);
        self.push_front(slot);

        if self.len() > self.capacity {
            self.evict();
        }
    }

    /// Removes `key`; returns whether it was present.
    fn remove(&mut self, key: &[u8]) -> bool {
        let Some(slot) = self.index.remove(key) else {
            return false;
        };
        self.unlink(slot);
        self.release(slot);
        true
    }

    /// Removes the least recently used key.
    fn evict(&mut self) {
        let slot = self.tail;
        debug_assert_ne!(slot, NIL, "evicting from an empty cache");
        self.unlink(slot);
        let key = std::mem::take(&mut self.node_mut(slot).key);
        self.index.remove(&key);
        self.release(slot);
    }

    /// Returns an unlinked slot to the free list, dropping its buffers.
    fn release(&mut self, slot: Slot) {
        let node = self.node_mut(slot);
        node.key = Box::default();
        node.value = Vec::new();
        self.free.push(slot);
    }

    fn move_to_front(&mut self, slot: Slot) {
        if self.head != slot {
            self.unlink(slot);
            self.push_front(slot);
        }
    }

    /// Links an unlinked node in as the most recently used.
    fn push_front(&mut self, slot: Slot) {
        let old_head = self.head;
        let node = self.node_mut(slot);
        node.prev = NIL;
        node.next = old_head;
        if old_head == NIL {
            self.tail = slot;
        } else {
            self.node_mut(old_head).prev = slot;
        }
        self.head = slot;
    }

    /// Detaches a linked node from the list, leaving its own links stale.
    fn unlink(&mut self, slot: Slot) {
        let Node { prev, next, .. } = *self.node(slot);
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

    fn node(&self, slot: Slot) -> &Node {
        &self.nodes[slot as usize]
    }

    fn node_mut(&mut self, slot: Slot) -> &mut Node {
        &mut self.nodes[slot as usize]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn simulate(input: &str) -> String {
        let mut output = Vec::new();
        run(input.as_bytes(), &mut output).expect("simulation failed");
        String::from_utf8(output).expect("output is not UTF-8")
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(simulate(input), "1\nNULL\n2\n");
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let input = "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c\n";
        assert_eq!(simulate(input), "9\nNULL\n3\n");
    }

    #[test]
    fn get_refreshes_recency() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\nGET c";
        assert_eq!(simulate(input), "1\n1\nNULL\n3\n");
    }

    #[test]
    fn delete_reports_presence_and_frees_room() {
        let input = "2\nSET x 1\nSET y 2\nDEL x\nDEL x\nSET z 3\nSIZE\nGET y\nGET z\n";
        assert_eq!(simulate(input), "1\n0\n2\n2\n3\n");
    }

    #[test]
    fn capacity_one() {
        let input = "1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\nDEL b\nSIZE\nSET c 3\nGET c\n";
        assert_eq!(simulate(input), "NULL\n2\n1\n1\n0\n3\n");
    }

    #[test]
    fn last_line_without_newline_and_crlf() {
        assert_eq!(simulate("3\r\nSET a 1\r\nGET a"), "1\n");
    }

    #[test]
    fn empty_input_prints_nothing() {
        assert_eq!(simulate(""), "");
    }

    #[test]
    fn malformed_lines_are_ignored() {
        let input = "2\n\nFOO\nSET a\nGET\nSET a 1 2\nGET a b\nSIZE x\nSET a 1\nGET a\n";
        assert_eq!(simulate(input), "1\n");
    }

    #[test]
    fn invalid_capacity_is_an_error() {
        for input in ["0\n", "abc\n", "1000001\n"] {
            let error = run(input.as_bytes(), Vec::new()).unwrap_err();
            assert_eq!(error.kind(), io::ErrorKind::InvalidData, "input {input:?}");
        }
    }

    #[test]
    fn slots_are_reused() {
        let mut cache = LruCache::with_capacity(2);
        for round in 0..100u32 {
            let key = round.to_string();
            cache.set(key.as_bytes(), b"v");
            if round % 3 == 0 {
                assert!(cache.remove(key.as_bytes()));
            }
        }
        assert!(cache.len() <= 2);
        assert!(cache.nodes.len() <= 3);
    }

    #[test]
    fn matches_naive_model() {
        // Deterministic pseudo-random workload checked against an O(n) reference model.
        let mut state = 0x2545_f491_4f6c_dd1d_u64;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let capacity = 7;
        let mut cache = LruCache::with_capacity(capacity);
        let mut model: Vec<(Vec<u8>, Vec<u8>)> = Vec::new(); // most recent last
        for _ in 0..20_000 {
            let key = format!("k{}", next() % 20).into_bytes();
            match next() % 3 {
                0 => {
                    let value = format!("v{}", next() % 1000).into_bytes();
                    cache.set(&key, &value);
                    model.retain(|(k, _)| *k != key);
                    model.push((key, value));
                    if model.len() > capacity {
                        model.remove(0);
                    }
                }
                1 => {
                    let expected = model.iter().position(|(k, _)| *k == key).map(|at| {
                        let entry = model.remove(at);
                        model.push(entry);
                        model.last().unwrap().1.clone()
                    });
                    assert_eq!(cache.get(&key).map(<[u8]>::to_vec), expected);
                }
                _ => {
                    let at = model.iter().position(|(k, _)| *k == key);
                    if let Some(at) = at {
                        model.remove(at);
                    }
                    assert_eq!(cache.remove(&key), at.is_some());
                }
            }
            assert_eq!(cache.len(), model.len());
        }
    }
}
