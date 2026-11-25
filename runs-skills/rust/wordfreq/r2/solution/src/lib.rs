//! Word-frequency counting over arbitrary byte input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are compared case-insensitively (folded to ASCII lowercase).

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

/// A small, fast multiplicative hasher (FxHash-style) for short byte-string keys.
///
/// Inputs are not adversarial here, so `SipHash`'s `DoS` resistance is not needed.
#[derive(Default, Clone, Copy)]
pub struct FxHasher {
    hash: u64,
}

const SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

impl FxHasher {
    #[inline]
    fn add(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let (chunks, rest) = bytes.as_chunks::<8>();
        for chunk in chunks {
            self.add(u64::from_le_bytes(*chunk));
        }
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

type FxBuildHasher = BuildHasherDefault<FxHasher>;

/// Word counts keyed by lowercase word bytes borrowed from the input buffer.
pub type Counts<'a> = HashMap<&'a [u8], u64, FxBuildHasher>;

/// Counts words in `input`, folding it to ASCII lowercase in place.
///
/// The returned map borrows the (now lowercased) words from `input`.
pub fn count_words(input: &mut [u8]) -> Counts<'_> {
    input.make_ascii_lowercase();
    let mut counts = Counts::default();
    for word in input
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Returns the `n` most frequent words, ordered by count descending and then
/// by word ascending (byte order).
#[must_use]
pub fn top_n<'a>(counts: &Counts<'a>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<(&'a [u8], u64)> = counts.iter().map(|(&w, &c)| (w, c)).collect();
    let order = |a: &(&[u8], u64), b: &(&[u8], u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0));
    if n == 0 {
        return Vec::new();
    }
    if entries.len() > n {
        entries.select_nth_unstable_by(n - 1, order);
        entries.truncate(n);
    }
    entries.sort_unstable_by(order);
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &[u8]) -> Vec<(String, u64)> {
        let mut buf = input.to_vec();
        let counts = count_words(&mut buf);
        top_n(&counts, 10)
            .into_iter()
            .map(|(w, c)| (String::from_utf8_lossy(w).into_owned(), c))
            .collect()
    }

    fn pairs(v: &[(&str, u64)]) -> Vec<(String, u64)> {
        v.iter().map(|&(w, c)| (w.to_owned(), c)).collect()
    }

    #[test]
    fn simple_example() {
        assert_eq!(
            run(b"The cat and the hat."),
            pairs(&[("the", 2), ("and", 1), ("cat", 1), ("hat", 1)])
        );
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(
            run(b"don't stop_me 4now, now-NOW\xffnow\xc3\xa9x"),
            pairs(&[
                ("now", 4),
                ("don", 1),
                ("me", 1),
                ("stop", 1),
                ("t", 1),
                ("x", 1)
            ])
        );
    }

    #[test]
    fn empty_and_no_words() {
        assert!(run(b"").is_empty());
        assert!(run(b"123 _ ' \x80\xff").is_empty());
    }

    #[test]
    fn limits_to_ten_with_ties() {
        let out = run(b"k j i h g f e d c b a a");
        assert_eq!(out.len(), 10);
        assert_eq!(out[0], ("a".to_owned(), 2));
        assert_eq!(out[9], ("j".to_owned(), 1));
    }
}
