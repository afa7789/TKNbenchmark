//! `lru`: an LRU cache simulator driven by `SET` / `GET` / `DEL` / `SIZE` commands.

use std::collections::HashMap;
use std::io::{self, Write};

/// Runs the command script in `input`: a capacity line followed by one command per line.
pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    let mut lines = input
        .split(|&b| b == b'\n')
        .map(|line| line.strip_suffix(b"\r").unwrap_or(line));
    let capacity = lines
        .next()
        .and_then(|line| std::str::from_utf8(line).ok())
        .and_then(|s| s.trim().parse::<usize>().ok())
        .filter(|&c| c >= 1)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid capacity line"))?;

    let mut cache = LruCache::new(capacity);
    for line in lines {
        let mut tokens = line.split(|&b| b == b' ');
        match (tokens.next(), tokens.next(), tokens.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.set(key, value),
            (Some(b"GET"), Some(key), _) => {
                out.write_all(cache.get(key).unwrap_or(b"NULL"))?;
                out.write_all(b"\n")?;
            }
            (Some(b"DEL"), Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), _, _) => writeln!(out, "{}", cache.len())?,
            _ => {} // Blank or malformed line: ignored.
        }
    }
    Ok(())
}

const NIL: u32 = u32::MAX;

struct Node {
    key: Box<[u8]>,
    value: Vec<u8>,
    prev: u32,
    next: u32,
}

/// A fixed-capacity LRU cache: a hash map into a slab-allocated doubly linked list.
/// `head` is the most recently used entry, `tail` the least.
struct LruCache {
    capacity: usize,
    index: HashMap<Box<[u8]>, u32>,
    nodes: Vec<Node>,
    free: Vec<u32>,
    head: u32,
    tail: u32,
}

impl LruCache {
    fn new(capacity: usize) -> Self {
        let reserve = capacity.min(1 << 16);
        Self {
            capacity,
            index: HashMap::with_capacity(reserve),
            nodes: Vec::with_capacity(reserve),
            free: Vec::new(),
            head: NIL,
            tail: NIL,
        }
    }

    fn len(&self) -> usize {
        self.index.len()
    }

    fn get(&mut self, key: &[u8]) -> Option<&[u8]> {
        let id = *self.index.get(key)?;
        self.move_to_front(id);
        Some(&self.nodes[id as usize].value)
    }

    fn set(&mut self, key: &[u8], value: &[u8]) {
        if let Some(&id) = self.index.get(key) {
            let node = &mut self.nodes[id as usize];
            node.value.clear();
            node.value.extend_from_slice(value);
            self.move_to_front(id);
            return;
        }
        let key: Box<[u8]> = key.into();
        let node = Node {
            key: key.clone(),
            value: value.to_vec(),
            prev: NIL,
            next: NIL,
        };
        let id = if let Some(id) = self.free.pop() {
            self.nodes[id as usize] = node;
            id
        } else {
            let id = u32::try_from(self.nodes.len()).expect("cache slab exceeds u32 indices");
            self.nodes.push(node);
            id
        };
        self.index.insert(key, id);
        self.push_front(id);
        if self.index.len() > self.capacity {
            let lru = self.tail;
            let evicted = std::mem::take(&mut self.nodes[lru as usize].key);
            self.index.remove(&evicted);
            self.release(lru);
        }
    }

    fn remove(&mut self, key: &[u8]) -> bool {
        match self.index.remove(key) {
            Some(id) => {
                self.release(id);
                true
            }
            None => false,
        }
    }

    /// Unlinks a node whose key is already gone from the index and recycles its slot.
    fn release(&mut self, id: u32) {
        self.unlink(id);
        let node = &mut self.nodes[id as usize];
        node.key = Box::default();
        node.value = Vec::new();
        self.free.push(id);
    }

    fn move_to_front(&mut self, id: u32) {
        if self.head != id {
            self.unlink(id);
            self.push_front(id);
        }
    }

    fn push_front(&mut self, id: u32) {
        let old_head = self.head;
        {
            let node = &mut self.nodes[id as usize];
            node.prev = NIL;
            node.next = old_head;
        }
        match old_head {
            NIL => self.tail = id,
            h => self.nodes[h as usize].prev = id,
        }
        self.head = id;
    }

    fn unlink(&mut self, id: u32) {
        let Node { prev, next, .. } = self.nodes[id as usize];
        match prev {
            NIL => self.head = next,
            p => self.nodes[p as usize].next = next,
        }
        match next {
            NIL => self.tail = prev,
            n => self.nodes[n as usize].prev = prev,
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
    fn overwrite_refreshes() {
        assert_eq!(
            render("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c"),
            "9\nNULL\n3\n"
        );
    }

    #[test]
    fn delete_and_reuse_slots() {
        assert_eq!(
            render("2\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\nSET y 2\nSET z 3\nSET w 4\nGET y\nGET w\nSIZE\n"),
            "1\n0\n0\nNULL\nNULL\n4\n2\n"
        );
    }
}
