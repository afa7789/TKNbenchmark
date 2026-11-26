//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
//!
//! A word is a maximal run of `[A-Za-z]`, folded to lowercase. Output is
//! `<count> <word>` ordered by count descending, then word ascending.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// 64-bit FNV-1a: fast for the short keys this program hashes.
struct Fnv1a(u64);

impl Default for Fnv1a {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for Fnv1a {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }
}

type FnvMap<K, V> = HashMap<K, V, BuildHasherDefault<Fnv1a>>;

/// Counts every word in `text`, lowercasing it in place.
fn count_words(text: &mut [u8]) -> FnvMap<&[u8], u64> {
    text.make_ascii_lowercase();
    let mut counts = FnvMap::default();
    for word in text
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Ranking order: count descending, then word ascending (byte order).
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the `n` highest-ranked words, best first.
fn top_words<'a>(counts: FnvMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        entries.select_nth_unstable_by(n, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = count_words(&mut input);
    let top = top_words(counts, TOP_N);

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("wordfreq: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &str) -> Vec<(String, u64)> {
        let mut bytes = input.as_bytes().to_vec();
        top_words(count_words(&mut bytes), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            top("The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators_and_empty() {
        assert!(top("").is_empty());
        assert!(top("123 _'\u{e9}").is_empty());
        assert_eq!(top("don't")[0], ("don".to_string(), 1));
    }

    #[test]
    fn truncates_to_top_n() {
        let words: String = (b'a'..=b'z').map(|c| format!("{} ", c as char)).collect();
        let result = top(&words);
        assert_eq!(result.len(), TOP_N);
        assert_eq!(result[0].0, "a");
        assert_eq!(result[9].0, "j");
    }
}
