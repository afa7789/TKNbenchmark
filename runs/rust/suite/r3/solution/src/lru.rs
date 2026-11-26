//! `lru`: simulate a least-recently-used cache driven by text commands.
//!
//! Entries live in a slab (`Vec<Node>`) threaded by an intrusive doubly linked
//! list ordered from most to least recently used; a hash map indexes the slab
//! by key. Every command is O(1) expected time.

use std::io::{self, Write};

use crate::fxhash::FxHashMap;

pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n').map(trim_cr);
    let Some(capacity) = lines.next().and_then(parse_capacity) else {
        return Ok(());
    };
    let mut cache = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        match (tokens.next(), tokens.next(), tokens.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.set(key, value),
            (Some(b"GET"), Some(key), _) => {
                out.write_all(cache.get(key).unwrap_or(b"NULL"))?;
                out.write_all(b"\n")?;
            }
            (Some(b"DEL"), Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), _, _) => {
                out.write_all(cache.len().to_string().as_bytes())?;
                out.write_all(b"\n")?;
            }
            // Blank or malformed lines have no effect.
            _ => {}
        }
    }
    Ok(())
}

fn trim_cr(line: &[u8]) -> &[u8] {
    line.strip_suffix(b"\r").unwrap_or(line)
}

fn parse_capacity(line: &[u8]) -> Option<usize> {
    std::str::from_utf8(line)
        .ok()?
        .trim()
        .parse()
        .ok()
        .filter(|&c| c >= 1)
}

/// Sentinel index meaning "no node".
const NIL: usize = usize::MAX;

struct Node {
    key: Box<[u8]>,
    value: Box<[u8]>,
    prev: usize,
    next: usize,
}

pub struct LruCache {
    capacity: usize,
    index: FxHashMap<Box<[u8]>, usize>,
    nodes: Vec<Node>,
    /// Slab slots released by deletions, available for reuse.
    free: Vec<usize>,
    /// Most recently used node.
    head: usize,
    /// Least recently used node.
    tail: usize,
}

impl LruCache {
    pub fn new(capacity: usize) -> Self {
        assert!(capacity >= 1, "LRU capacity must be at least 1");
        Self {
            capacity,
            index: FxHashMap::default(),
            nodes: Vec::new(),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    pub fn len(&self) -> usize {
        self.index.len()
    }

    pub fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let id = *self.index.get(key)?;
        self.promote(id);
        Some(&self.nodes[id].value)
    }

    pub fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&id) = self.index.get(key) {
            self.nodes[id].value = value.into();
            self.promote(id);
            return;
        }

        if self.len() == self.capacity {
            self.evict_lru();
        }
        let node = Node {
            key: key.into(),
            value: value.into(),
            prev: NIL,
            next: NIL,
        };
        let id = match self.free.pop() {
            Some(id) => {
                self.nodes[id] = node;
                id
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() - 1
            }
        };
        self.index.insert(key.into(), id);
        self.push_front(id);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(&mut self, key: &[u8]) -> bool {
        let Some(id) = self.index.remove(key) else {
            return false;
        };
        self.release(id);
        true
    }

    fn evict_lru(&mut self) {
        let id = self.tail;
        debug_assert_ne!(id, NIL, "evicting from an empty cache");
        self.index.remove(&self.nodes[id].key);
        self.release(id);
    }

    /// Unlinks node `id` and returns its slot to the free list.
    fn release(&mut self, id: usize) {
        self.unlink(id);
        let node = &mut self.nodes[id];
        node.key = Box::default();
        node.value = Box::default();
        self.free.push(id);
    }

    fn promote(&mut self, id: usize) {
        if self.head != id {
            self.unlink(id);
            self.push_front(id);
        }
    }

    fn unlink(&mut self, id: usize) {
        let Node { prev, next, .. } = self.nodes[id];
        match prev {
            NIL => self.head = next,
            p => self.nodes[p].next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.nodes[n].prev = prev,
        }
    }

    fn push_front(&mut self, id: usize) {
        let old_head = self.head;
        let node = &mut self.nodes[id];
        node.prev = NIL;
        node.next = old_head;
        match old_head {
            NIL => self.tail = id,
            h => self.nodes[h].prev = id,
        }
        self.head = id;
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
        assert_eq!(
            render("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n"),
            "1\nNULL\n2\n"
        );
    }

    #[test]
    fn overwrite_refreshes_recency() {
        assert_eq!(
            render("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c"),
            "9\nNULL\n3\n"
        );
    }

    #[test]
    fn delete_and_reuse_slots() {
        assert_eq!(
            render(
                "2\nSET x 1\nDEL x\nDEL x\nSIZE\nSET y 2\nSET z 3\nSET w 4\nGET y\nGET z\nGET w\nSIZE\n"
            ),
            "1\n0\n0\nNULL\n3\n4\n2\n"
        );
    }

    #[test]
    fn capacity_one() {
        assert_eq!(
            render("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n"),
            "NULL\n2\n1\n"
        );
    }
}
