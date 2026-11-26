//! `app wordfreq`: word frequencies (see SPEC.md, section `wordfreq`).
//!
//! A word is a maximal run of ASCII letters, folded to lowercase; every other
//! byte is a separator. The input is lowercased in place once, so words can be
//! counted as borrowed slices of the input buffer without per-word allocation.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};

/// How many of the most frequent words to print.
const TOP_N: usize = 10;

/// Entry point for `app wordfreq`: reads standard input, writes standard output.
pub fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    input.make_ascii_lowercase();

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    for (word, count) in top_words(&input, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

/// Splits `text` into maximal runs of ASCII letters.
///
/// Letters are returned as they appear; callers wanting case-insensitive
/// words must fold `text` beforehand.
fn words(text: &[u8]) -> impl Iterator<Item = &[u8]> {
    text.split(|byte| !byte.is_ascii_alphabetic())
        .filter(|word| !word.is_empty())
}

/// Returns the `n` most frequent words of `text` with their counts, ordered by
/// count descending, then by word ascending (byte order).
///
/// Words are compared byte for byte, so `text` should already be case-folded.
fn top_words(text: &[u8], n: usize) -> Vec<(&[u8], u64)> {
    let mut counts: HashMap<&[u8], u64, BuildFnv> = HashMap::default();
    for word in words(text) {
        *counts.entry(word).or_insert(0) += 1;
    }

    let mut ranked: Vec<(&[u8], u64)> = counts.into_iter().collect();
    // Order by frequency, most frequent first; break ties alphabetically.
    let rank = |a: &(&[u8], u64), b: &(&[u8], u64)| -> Ordering {
        b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
    };
    if ranked.len() > n {
        if n == 0 {
            return Vec::new();
        }
        // Partition so the first `n` entries are the top `n`, in O(len).
        ranked.select_nth_unstable_by(n - 1, rank);
        ranked.truncate(n);
    }
    ranked.sort_unstable_by(rank);
    ranked
}

/// Builds [`FnvHasher`]s for the word-count map.
type BuildFnv = BuildHasherDefault<FnvHasher>;

/// 64-bit FNV-1a: much faster than the default `SipHash` for the short keys
/// this module hashes. It is not DoS-resistant, which is acceptable for a
/// one-shot command-line tool processing its own input.
struct FnvHasher(u64);

impl Default for FnvHasher {
    fn default() -> Self {
        const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
        Self(OFFSET_BASIS)
    }
}

impl Hasher for FnvHasher {
    fn write(&mut self, bytes: &[u8]) {
        const PRIME: u64 = 0x0000_0100_0000_01b3;
        for &byte in bytes {
            self.0 ^= u64::from(byte);
            self.0 = self.0.wrapping_mul(PRIME);
        }
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(text: &str) -> Vec<(String, u64)> {
        let mut folded = text.as_bytes().to_vec();
        folded.make_ascii_lowercase();
        top_words(&folded, TOP_N)
            .into_iter()
            .map(|(word, count)| (String::from_utf8(word.to_vec()).unwrap(), count))
            .collect()
    }

    fn pairs(expected: &[(&str, u64)]) -> Vec<(String, u64)> {
        expected.iter().map(|&(w, c)| (w.to_owned(), c)).collect()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            top("The cat and the hat."),
            pairs(&[("the", 2), ("and", 1), ("cat", 1), ("hat", 1)])
        );
    }

    #[test]
    fn no_words() {
        assert!(top("").is_empty());
        assert!(top("123 _ ' !? \n\t").is_empty());
    }

    #[test]
    fn non_letters_separate_words() {
        assert_eq!(
            top("don't stop_me 4now, now-NOW"),
            pairs(&[("now", 3), ("don", 1), ("me", 1), ("stop", 1), ("t", 1)])
        );
    }

    #[test]
    fn non_ascii_bytes_are_separators() {
        let mut input = b"caf\xc3\xa9 caf\xff\xfeX".to_vec();
        input.make_ascii_lowercase();
        let result = top_words(&input, TOP_N);
        assert_eq!(result, vec![(&b"caf"[..], 2), (&b"x"[..], 1)]);
    }

    #[test]
    fn keeps_only_top_ten_with_ties_by_word() {
        let result = top("zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha");
        let words: Vec<&str> = result.iter().map(|(w, _)| w.as_str()).collect();
        assert_eq!(
            words,
            ["alpha", "beta", "eta", "iota", "kappa", "lambda", "mu", "nu", "omicron", "pi"]
        );
        assert_eq!(result[0].1, 2);
    }

    #[test]
    fn zero_limit_returns_nothing() {
        assert!(top_words(b"a b c", 0).is_empty());
    }
}
