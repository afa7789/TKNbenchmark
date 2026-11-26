//! Word tokenization and frequency counting.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

/// FNV-1a: much faster than SipHash for short keys; inputs here are not adversarial
/// enough to warrant DoS-resistant hashing.
#[derive(Clone, Copy)]
struct FnvHasher(u64);

impl Default for FnvHasher {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for FnvHasher {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 = (self.0 ^ u64::from(b)).wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn finish(&self) -> u64 {
        // Final avalanche so the low bits used for bucketing are well mixed.
        let mut h = self.0;
        h ^= h >> 33;
        h = h.wrapping_mul(0xff51_afd7_ed55_8ccd);
        h ^= h >> 33;
        h
    }
}

type FnvBuildHasher = BuildHasherDefault<FnvHasher>;

/// Counts occurrences of words borrowed from an input buffer.
pub struct WordCounter<'a> {
    counts: HashMap<&'a [u8], u64, FnvBuildHasher>,
}

impl<'a> WordCounter<'a> {
    /// Counts every maximal run of ASCII letters in `text`.
    ///
    /// Words are counted exactly as they appear; callers wanting case-insensitive
    /// counts should fold `text` to lowercase first.
    pub fn from_text(text: &'a [u8]) -> Self {
        let mut counts: HashMap<&[u8], u64, FnvBuildHasher> = HashMap::default();
        for word in text
            .split(|b| !b.is_ascii_alphabetic())
            .filter(|w| !w.is_empty())
        {
            *counts.entry(word).or_insert(0) += 1;
        }
        Self { counts }
    }

    /// Returns up to `limit` words ordered by count descending, then word ascending.
    pub fn top(&self, limit: usize) -> Vec<(&'a [u8], u64)> {
        if limit == 0 {
            return Vec::new();
        }
        let mut entries: Vec<(&'a [u8], u64)> =
            self.counts.iter().map(|(&w, &c)| (w, c)).collect();
        if entries.len() > limit {
            entries.select_nth_unstable_by(limit - 1, rank);
            entries.truncate(limit);
        }
        entries.sort_unstable_by(rank);
        entries
    }
}

fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(text: &str, limit: usize) -> Vec<(String, u64)> {
        let mut bytes = text.as_bytes().to_vec();
        bytes.make_ascii_lowercase();
        WordCounter::from_text(&bytes)
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
    fn separators_split_words() {
        let got = top("don't stop_me 4now, now-NOW", 10);
        let words: Vec<_> = got.iter().map(|(w, _)| w.as_str()).collect();
        assert_eq!(words, ["now", "don", "me", "stop", "t"]);
    }

    #[test]
    fn non_ascii_bytes_are_separators() {
        let mut bytes = b"caf\xc3\xa9 caf\xffe".to_vec();
        bytes.make_ascii_lowercase();
        let counter = WordCounter::from_text(&bytes);
        assert_eq!(counter.top(10), [(&b"caf"[..], 2), (&b"e"[..], 1)]);
    }

    #[test]
    fn limits_output() {
        assert_eq!(top("a b c d e", 2).len(), 2);
        assert!(top("", 10).is_empty());
        assert!(top("a", 0).is_empty());
    }
}
