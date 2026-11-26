//! Word frequency counting over a byte buffer.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

/// Counts occurrences of words borrowed from an input buffer.
///
/// A word is a maximal run of ASCII letters; every other byte is a separator.
/// Words are compared byte-for-byte, so callers wanting case-insensitive
/// counting should fold the input to lowercase first.
#[derive(Debug, Default)]
pub struct WordCounter<'a> {
    counts: HashMap<&'a [u8], u64, BuildHasherDefault<FxHasher>>,
}

impl<'a> WordCounter<'a> {
    /// Counts every word in `text`.
    pub fn from_text(text: &'a [u8]) -> Self {
        let mut counter = Self::default();
        for word in text
            .split(|b| !b.is_ascii_alphabetic())
            .filter(|w| !w.is_empty())
        {
            *counter.counts.entry(word).or_insert(0) += 1;
        }
        counter
    }

    /// Returns up to `limit` words ordered by count descending, then by word ascending.
    pub fn top(&self, limit: usize) -> Vec<(&'a [u8], u64)> {
        let mut entries: Vec<(&'a [u8], u64)> =
            self.counts.iter().map(|(&word, &count)| (word, count)).collect();
        if entries.len() > limit {
            if limit == 0 {
                return Vec::new();
            }
            entries.select_nth_unstable_by(limit - 1, rank);
            entries.truncate(limit);
        }
        entries.sort_unstable_by(rank);
        entries
    }
}

/// Orders "better" entries first: higher count, then lexicographically smaller word.
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// A fast, non-cryptographic hasher (the FxHash algorithm used by rustc).
///
/// Keys come from untrusted input, but the process is short-lived and
/// single-shot, so HashDoS resistance is traded for throughput.
#[derive(Debug, Default, Clone, Copy)]
struct FxHasher {
    hash: u64,
}

impl FxHasher {
    const SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

    #[inline]
    fn add(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(Self::SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let mut chunks = bytes.chunks_exact(8);
        for chunk in &mut chunks {
            self.add(u64::from_le_bytes(chunk.try_into().expect("chunk of 8 bytes")));
        }
        let rest = chunks.remainder();
        if !rest.is_empty() {
            let mut buf = [0u8; 8];
            buf[..rest.len()].copy_from_slice(rest);
            self.add(u64::from_le_bytes(buf));
        }
    }

    #[inline]
    fn write_u8(&mut self, i: u8) {
        self.add(u64::from(i));
    }

    #[inline]
    fn write_usize(&mut self, i: usize) {
        self.add(i as u64);
    }

    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(text: &str, limit: usize) -> Vec<(String, u64)> {
        let lower = text.to_ascii_lowercase();
        WordCounter::from_text(lower.as_bytes())
            .top(limit)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn counts_and_orders() {
        assert_eq!(
            top("The cat and the hat.", 10),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators() {
        assert_eq!(
            top("don't stop_me 4now, now-NOW", 10),
            [("now", 3), ("don", 1), ("me", 1), ("stop", 1), ("t", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn limits_and_empty() {
        assert!(top("", 10).is_empty());
        assert!(top("123 ...", 10).is_empty());
        assert!(top("a b c", 0).is_empty());
        assert_eq!(top("c b a b", 2).len(), 2);
    }
}
