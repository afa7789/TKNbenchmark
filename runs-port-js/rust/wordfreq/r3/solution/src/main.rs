//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and ranked by count descending, then by
//! word ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// A small, fast non-cryptographic hasher (FNV-1a over 64-bit words).
///
/// Keys are short ASCII words from local input, so HashDoS resistance is not
/// a concern and SipHash's overhead is not worth paying.
#[derive(Default)]
struct WordHasher(u64);

impl Hasher for WordHasher {
    fn write(&mut self, bytes: &[u8]) {
        const PRIME: u64 = 0x0000_0100_0000_01b3;
        let mut hash = if self.0 == 0 { 0xcbf2_9ce4_8422_2325 } else { self.0 };
        let mut chunks = bytes.chunks_exact(8);
        for chunk in &mut chunks {
            let word = u64::from_le_bytes(chunk.try_into().expect("chunk of 8 bytes"));
            hash = (hash ^ word).wrapping_mul(PRIME);
        }
        for &byte in chunks.remainder() {
            hash = (hash ^ u64::from(byte)).wrapping_mul(PRIME);
        }
        self.0 = hash;
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

type Counts<'a> = HashMap<&'a [u8], u64, BuildHasherDefault<WordHasher>>;

/// Lowercases `data` in place and counts every word, borrowing keys from it.
fn count_words(data: &mut [u8]) -> Counts<'_> {
    data.make_ascii_lowercase();
    let data: &[u8] = data;
    let mut counts = Counts::default();
    for word in data
        .split(|byte| !byte.is_ascii_lowercase())
        .filter(|word| !word.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Ranking order: count descending, then word ascending.
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the top `n` entries in rank order without sorting the whole map.
fn top_entries<'a>(counts: &Counts<'a>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts.iter().map(|(&word, &count)| (word, count)).collect();
    if entries.len() > n && n > 0 {
        entries.select_nth_unstable_by(n - 1, rank);
    }
    entries.truncate(n);
    entries.sort_unstable_by(rank);
    entries
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = count_words(&mut input);
    let top = top_entries(&counts, TOP_N);

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
        // A closed stdout (e.g. piped into `head`) is not an error worth reporting.
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
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
        let mut data = input.as_bytes().to_vec();
        let counts = count_words(&mut data);
        top_entries(&counts, TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn counts_and_orders() {
        assert_eq!(
            top("The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators() {
        let words: Vec<_> = top("don't stop_me 4now, now-NOW").into_iter().map(|(w, _)| w).collect();
        assert_eq!(words, ["now", "don", "me", "stop", "t"]);
    }

    #[test]
    fn non_ascii_bytes_separate() {
        let mut data = b"caf\xc3\xa9x\xffY".to_vec();
        let counts = count_words(&mut data);
        let words: Vec<_> = top_entries(&counts, TOP_N).into_iter().map(|(w, _)| w.to_vec()).collect();
        assert_eq!(words, [b"caf".to_vec(), b"x".to_vec(), b"y".to_vec()]);
    }

    #[test]
    fn empty() {
        assert!(top("").is_empty());
        assert!(top("123 _'").is_empty());
    }

    #[test]
    fn limits_to_ten() {
        assert_eq!(top("a b c d e f g h i j k l").len(), TOP_N);
    }
}
