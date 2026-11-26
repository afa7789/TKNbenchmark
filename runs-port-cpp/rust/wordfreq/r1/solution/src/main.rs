//! wordfreq: print the 10 most frequent ASCII-letter words read from stdin.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};

const TOP_N: usize = 10;

/// Counts lowercase words in `input`, folding ASCII letters to lowercase in place.
///
/// A word is a maximal run of ASCII letters; every other byte is a separator.
/// The returned map borrows its keys from `input`.
fn count_words(input: &mut [u8]) -> HashMap<&[u8], u64> {
    input.make_ascii_lowercase();
    let input: &[u8] = input;

    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in input
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Orders entries by count descending, then by word ascending (byte order).
fn by_rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the `n` highest-ranked entries, in rank order.
fn top_words<'a>(counts: HashMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        if n == 0 {
            return Vec::new();
        }
        entries.select_nth_unstable_by(n - 1, by_rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(by_rank);
    entries
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = count_words(&mut input);

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_words(counts, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(text: &str) -> Vec<(String, u64)> {
        let mut buf = text.as_bytes().to_vec();
        top_words(count_words(&mut buf), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        let got = run("The cat and the hat.");
        let want = [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)];
        assert_eq!(got, want.map(|(w, c)| (w.to_string(), c)));
    }

    #[test]
    fn separators() {
        let got = run("don't stop_me 4now, now-NOW");
        let want = [("now", 3), ("don", 1), ("me", 1), ("stop", 1), ("t", 1)];
        assert_eq!(got, want.map(|(w, c)| (w.to_string(), c)));
    }

    #[test]
    fn empty() {
        assert!(run("").is_empty());
        assert!(run("123 _ !!").is_empty());
    }

    #[test]
    fn non_ascii_bytes_separate() {
        let mut buf = b"ab\xffcd\xc3(ab".to_vec();
        let got = top_words(count_words(&mut buf), TOP_N);
        assert_eq!(got, vec![(&b"ab"[..], 2), (&b"cd"[..], 1)]);
    }
}
