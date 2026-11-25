//! Word-frequency counting over arbitrary bytes.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to ASCII lowercase before counting.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, Write};

/// Fast non-cryptographic hasher (FxHash-style) for short byte-string keys.
///
/// The keys are words from the input, so `HashDoS` resistance is not needed and
/// `SipHash` would dominate the run time.
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
        let mut tail = [0u8; 8];
        tail[..rest.len()].copy_from_slice(rest);
        self.add(u64::from_le_bytes(tail));
    }

    #[inline]
    fn write_usize(&mut self, n: usize) {
        self.add(n as u64);
    }

    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

/// Map from lowercase word to its number of occurrences.
pub type WordCounts = HashMap<Box<[u8]>, u64, BuildHasherDefault<FxHasher>>;

/// Counts every word in `input`, folding ASCII letters to lowercase.
#[must_use]
pub fn count_words(input: &[u8]) -> WordCounts {
    let mut counts = WordCounts::default();
    let mut word = Vec::with_capacity(64);

    for chunk in input.split(|b| !b.is_ascii_alphabetic()) {
        if chunk.is_empty() {
            continue;
        }
        word.clear();
        word.extend(chunk.iter().map(u8::to_ascii_lowercase));
        // Look up by slice first so repeated words never allocate.
        if let Some(n) = counts.get_mut(word.as_slice()) {
            *n += 1;
        } else {
            counts.insert(word.as_slice().into(), 1);
        }
    }
    counts
}

/// Report ordering: count descending, then word ascending (byte order).
fn rank(a: &(Box<[u8]>, u64), b: &(Box<[u8]>, u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0))
}

/// Returns at most `n` `(word, count)` pairs in report order.
#[must_use]
pub fn top_words(counts: WordCounts, n: usize) -> Vec<(Box<[u8]>, u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if n == 0 {
        return Vec::new();
    }
    if entries.len() > n {
        entries.select_nth_unstable_by(n - 1, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

/// Writes one `<count> <word>` line per entry.
///
/// # Errors
/// Propagates any error from `out`.
pub fn write_report<W: Write>(out: &mut W, entries: &[(Box<[u8]>, u64)]) -> io::Result<()> {
    for (word, count) in entries {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(input: &[u8]) -> String {
        let top = top_words(count_words(input), 10);
        let mut out = Vec::new();
        write_report(&mut out, &top).expect("writing to a Vec cannot fail");
        String::from_utf8(out).expect("words are ASCII")
    }

    #[test]
    fn example() {
        assert_eq!(
            report(b"The cat and the hat."),
            "2 the\n1 and\n1 cat\n1 hat\n"
        );
    }

    #[test]
    fn empty_and_wordless() {
        assert_eq!(report(b""), "");
        assert_eq!(report(b"123 _ ' \xff\xc3("), "");
    }

    #[test]
    fn separators_and_non_ascii() {
        assert_eq!(
            report(b"don't stop_me 4now, now-NOW caf\xc3\xa9"),
            "3 now\n1 caf\n1 don\n1 me\n1 stop\n1 t\n"
        );
    }

    #[test]
    fn limits_to_ten_with_ties() {
        let out =
            report(b"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha");
        assert_eq!(
            out,
            "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n"
        );
    }

    #[test]
    fn long_words_hash_consistently() {
        let input = b"Supercalifragilisticexpialidocious supercalifragilisticexpialidocious";
        assert_eq!(report(input), "2 supercalifragilisticexpialidocious\n");
    }
}
