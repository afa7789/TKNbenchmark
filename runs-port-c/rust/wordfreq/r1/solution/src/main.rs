//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words
//! (case-folded), ordered by count descending, then word ascending.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// 64-bit FNV-1a: fast for the short keys we hash, and deterministic.
struct FnvHasher(u64);

impl Default for FnvHasher {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for FnvHasher {
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

type FnvMap<K, V> = HashMap<K, V, BuildHasherDefault<FnvHasher>>;

/// Counts occurrences of each case-folded word in `input`.
///
/// The input is lowercased in place so that words can be looked up as
/// borrowed slices; a key is only allocated the first time a word is seen.
fn count_words(input: &mut [u8]) -> FnvMap<Box<[u8]>, u64> {
    input.make_ascii_lowercase();
    let mut counts = FnvMap::default();
    for word in input
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
    {
        match counts.get_mut(word) {
            Some(count) => *count += 1,
            None => {
                counts.insert(Box::from(word), 1);
            }
        }
    }
    counts
}

/// Ranking order: count descending, then word ascending (byte order).
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the `n` highest-ranked words, best first.
fn top_words(counts: &FnvMap<Box<[u8]>, u64>, n: usize) -> Vec<(&[u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts.iter().map(|(w, &c)| (&**w, c)).collect();
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

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_words(&counts, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wordfreq: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &str) -> Vec<(String, u64)> {
        let mut bytes = input.as_bytes().to_vec();
        let counts = count_words(&mut bytes);
        top_words(&counts, TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            top("The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators_and_empty() {
        assert!(top("").is_empty());
        assert!(top("123 _ '\u{e9}").is_empty());
        assert_eq!(top("don't stop_me 4now, now-NOW")[0], ("now".to_string(), 3));
    }

    #[test]
    fn limits_to_top_n() {
        let input: String = (b'a'..=b'z').map(|c| format!("{} ", c as char)).collect();
        let result = top(&input);
        assert_eq!(result.len(), TOP_N);
        assert_eq!(result[0].0, "a");
        assert_eq!(result[9].0, "j");
    }
}
