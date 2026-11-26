//! `app lru`: an LRU cache simulator (see SPEC.md, section `lru`).
//!
//! The cache is a hash map from key to slot index plus an intrusive doubly
//! linked list threaded through a slot arena (`Vec<Node>`). Indices instead of
//! pointers keep it safe, and freed slots are recycled, so every command runs
//! in O(1) expected time with no per-command allocation once the arena is warm.

use std::collections::HashMap;
use std::io::{self, BufRead, BufWriter, Write};

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

/// Largest capacity the spec allows.
const MAX_CAPACITY: usize = 1_000_000;

/// Entry point for `app lru`: reads standard input, writes standard output.
pub fn run() -> io::Result<()> {
    let stdin = io::stdin().lock();
    let stdout = io::stdout().lock();
    simulate(
        io::BufReader::with_capacity(1 << 16, stdin),
        BufWriter::with_capacity(1 << 16, stdout),
    )
}

/// Runs the simulator: the first line of `input` is the capacity, every
/// later line a command whose output (if any) is written to `output`.
fn simulate(mut input: impl BufRead, mut output: impl Write) -> io::Result<()> {
    let mut line = Vec::new();
    if input.read_until(b'\n', &mut line)? == 0 {
        return Ok(());
    }
    let capacity = parse_capacity(&line)?;
    let mut cache = LruCache::new(capacity);

    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            break;
        }
        let Some(command) = Command::parse(strip_line_ending(&line)) else {
            // Blank or malformed lines produce no output.
            continue;
        };
        match command {
            Command::Set(key, value) => cache.set(key, value),
            Command::Get(key) => match cache.get(key) {
                Some(value) => {
                    output.write_all(value)?;
                    output.write_all(b"\n")?;
                }
                None => output.write_all(b"NULL\n")?,
            },
            Command::Del(key) => {
                output.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            Command::Size => writeln!(output, "{}", cache.len())?,
        }
    }
    output.flush()
}

fn parse_capacity(line: &[u8]) -> io::Result<usize> {
    std::str::from_utf8(line)
        .ok()
        .and_then(|text| text.trim().parse::<usize>().ok())
        .filter(|capacity| (1..=MAX_CAPACITY).contains(capacity))
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("capacity must be an integer in 1..={MAX_CAPACITY}"),
            )
        })
}

/// Strips a trailing `\n` (and a `\r` before it, for tolerance of CRLF input).
fn strip_line_ending(line: &[u8]) -> &[u8] {
    let line = line.strip_suffix(b"\n").unwrap_or(line);
    line.strip_suffix(b"\r").unwrap_or(line)
}

/// One parsed input command, borrowing its operands from the input line.
#[derive(Debug, PartialEq, Eq)]
enum Command<'a> {
    Set(&'a [u8], &'a [u8]),
    Get(&'a [u8]),
    Del(&'a [u8]),
    Size,
}

impl<'a> Command<'a> {
    /// Parses a line (without its terminator); `None` if it is not a command.
    fn parse(line: &'a [u8]) -> Option<Self> {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        let command = match (tokens.next()?, tokens.next(), tokens.next()) {
            (b"SET", Some(key), Some(value)) => Command::Set(key, value),
            (b"GET", Some(key), None) => Command::Get(key),
            (b"DEL", Some(key), None) => Command::Del(key),
            (b"SIZE", None, None) => Command::Size,
            _ => return None,
        };
        tokens.next().is_none().then_some(command)
    }
}

/// A slot in the arena: an entry plus its links in the recency list.
#[derive(Debug)]
struct Node {
    key: Box<[u8]>,
    value: Vec<u8>,
    /// Neighbour towards the most recently used end.
    prev: usize,
    /// Neighbour towards the least recently used end.
    next: usize,
}

/// A fixed-capacity map that evicts its least recently used key on overflow.
#[derive(Debug)]
struct LruCache {
    capacity: usize,
    map: HashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    /// Indices of unused slots in `nodes`, ready for reuse.
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
            map: HashMap::new(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    fn len(&self) -> usize {
        self.map.len()
    }

    /// Returns the value for `key`, marking it most recently used.
    fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let index = *self.map.get(key)?;
        self.move_to_front(index);
        Some(&self.nodes[index].value)
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting
    /// the least recently used key if the cache would exceed its capacity.
    fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&index) = self.map.get(key) {
            let node = &mut self.nodes[index];
            node.value.clear();
            node.value.extend_from_slice(value);
            self.move_to_front(index);
            return;
        }

        // Evicting before inserting is equivalent to the spec's
        // insert-then-evict: the new key is never the least recently used.
        if self.map.len() == self.capacity {
            self.evict_lru();
        }

        let key: Box<[u8]> = key.into();
        let node = Node {
            key: key.clone(),
            value: value.to_vec(),
            prev: NIL,
            next: NIL,
        };
        let index = if let Some(index) = self.free.pop() {
            self.nodes[index] = node;
            index
        } else {
            self.nodes.push(node);
            self.nodes.len() - 1
        };
        self.map.insert(key, index);
        self.push_front(index);
    }

    /// Removes `key`, returning whether it was present.
    fn remove(&mut self, key: &[u8]) -> bool {
        match self.map.remove(key) {
            Some(index) => {
                self.release(index);
                true
            }
            None => false,
        }
    }

    fn evict_lru(&mut self) {
        let index = self.tail;
        debug_assert_ne!(index, NIL, "evicting from an empty cache");
        self.map.remove(&self.nodes[index].key);
        self.release(index);
    }

    /// Unlinks a slot whose map entry is already gone and recycles it.
    fn release(&mut self, index: usize) {
        self.unlink(index);
        let node = &mut self.nodes[index];
        node.key = Box::default();
        node.value = Vec::new();
        self.free.push(index);
    }

    fn move_to_front(&mut self, index: usize) {
        if self.head != index {
            self.unlink(index);
            self.push_front(index);
        }
    }

    fn unlink(&mut self, index: usize) {
        let Node { prev, next, .. } = self.nodes[index];
        match prev {
            NIL => self.head = next,
            prev => self.nodes[prev].next = next,
        }
        match next {
            NIL => self.tail = prev,
            next => self.nodes[next].prev = prev,
        }
        let node = &mut self.nodes[index];
        node.prev = NIL;
        node.next = NIL;
    }

    fn push_front(&mut self, index: usize) {
        let old_head = self.head;
        let node = &mut self.nodes[index];
        node.prev = NIL;
        node.next = old_head;
        match old_head {
            NIL => self.tail = index,
            old_head => self.nodes[old_head].prev = index,
        }
        self.head = index;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_str(input: &str) -> String {
        let mut out = Vec::new();
        simulate(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(run_str(input), "1\nNULL\n2\n");
    }

    #[test]
    fn overwrite_refreshes_recency() {
        let input = "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c";
        assert_eq!(run_str(input), "9\nNULL\n3\n");
    }

    #[test]
    fn delete_and_size() {
        let input = "3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n";
        assert_eq!(run_str(input), "1\n0\n0\nNULL\n");
    }

    #[test]
    fn capacity_one() {
        let input = "1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n";
        assert_eq!(run_str(input), "NULL\n2\n1\n");
    }

    #[test]
    fn freed_slots_are_reused_consistently() {
        let input = "2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n";
        assert_eq!(run_str(input), "1\nNULL\n3\n4\n2\n");
    }

    #[test]
    fn get_refreshes_recency() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\n";
        assert_eq!(run_str(input), "1\n1\nNULL\n");
    }

    #[test]
    fn empty_input_prints_nothing() {
        assert_eq!(run_str(""), "");
        assert_eq!(run_str("5\n"), "");
    }

    #[test]
    fn rejects_invalid_capacity() {
        let mut out = Vec::new();
        assert!(simulate("0\n".as_bytes(), &mut out).is_err());
        assert!(simulate("abc\n".as_bytes(), &mut out).is_err());
    }

    #[test]
    fn parses_commands() {
        assert_eq!(Command::parse(b"SET k v"), Some(Command::Set(b"k", b"v")));
        assert_eq!(Command::parse(b"GET k"), Some(Command::Get(b"k")));
        assert_eq!(Command::parse(b"DEL k"), Some(Command::Del(b"k")));
        assert_eq!(Command::parse(b"SIZE"), Some(Command::Size));
        assert_eq!(Command::parse(b""), None);
        assert_eq!(Command::parse(b"GET"), None);
        assert_eq!(Command::parse(b"SET k"), None);
        assert_eq!(Command::parse(b"NOPE k"), None);
    }
}
