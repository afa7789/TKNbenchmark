//! Prints the ten most frequent ASCII-letter words read from standard input.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

/// Number of words to report.
const TOP_N: usize = 10;

/// FNV-1a: fast and well distributed for short byte-string keys.
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
        self.0
    }
}

type WordCounts<'a> = HashMap<&'a [u8], u64, BuildHasherDefault<FnvHasher>>;

/// Counts the words of `text`, which must already be lowercased.
///
/// A word is a maximal run of ASCII letters; every other byte separates words.
fn count_words(text: &[u8]) -> WordCounts<'_> {
    let mut counts = WordCounts::default();
    for word in text
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Returns up to `limit` entries ordered by count descending, then word ascending.
fn top_words<'a>(counts: WordCounts<'a>, limit: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    let order = |a: &(&[u8], u64), b: &(&[u8], u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0));
    if entries.len() > limit {
        entries.select_nth_unstable_by(limit, order);
        entries.truncate(limit);
    }
    entries.sort_unstable_by(order);
    entries
}

fn run() -> io::Result<()> {
    let mut text = Vec::new();
    io::stdin().lock().read_to_end(&mut text)?;
    text.make_ascii_lowercase();

    let counts = count_words(&text);
    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_words(counts, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
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
        let text = input.to_ascii_lowercase();
        top_words(count_words(text.as_bytes()), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            top("The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)].map(|(w, c)| (w.to_owned(), c))
        );
    }

    #[test]
    fn separators_and_empty() {
        assert!(top("").is_empty());
        assert!(top("123 _ '!").is_empty());
        let words: Vec<_> = top("don't stop_me 4now, now-NOW").into_iter().map(|(w, _)| w).collect();
        assert_eq!(words, ["now", "don", "me", "stop", "t"]);
    }

    #[test]
    fn limits_to_top_n() {
        let input: String = ('a'..='z').map(|c| format!("{c} ")).collect();
        let result = top(&input);
        assert_eq!(result.len(), TOP_N);
        assert_eq!(result[0].0, "a");
        assert_eq!(result[9].0, "j");
    }
}
