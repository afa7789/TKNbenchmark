//! wordfreq: print the 10 most frequent ASCII words read from standard input.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};

/// Maximum number of words to report.
const TOP_N: usize = 10;

/// Counts case-folded words, where a word is a maximal run of ASCII letters.
fn count_words(input: &[u8]) -> HashMap<Vec<u8>, u64> {
    let mut counts: HashMap<Vec<u8>, u64> = HashMap::new();
    let mut word = Vec::new();

    let mut record = |word: &mut Vec<u8>| {
        if word.is_empty() {
            return;
        }
        match counts.get_mut(word.as_slice()) {
            Some(count) => *count += 1,
            None => {
                counts.insert(word.clone(), 1);
            }
        }
        word.clear();
    };

    for &byte in input {
        if byte.is_ascii_alphabetic() {
            word.push(byte.to_ascii_lowercase());
        } else {
            record(&mut word);
        }
    }
    record(&mut word);

    counts
}

/// Orders by count descending, then word ascending (byte order).
fn rank(a: &(Vec<u8>, u64), b: &(Vec<u8>, u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0))
}

/// Returns the `n` highest-ranked words in rank order.
fn top_words(counts: HashMap<Vec<u8>, u64>, n: usize) -> Vec<(Vec<u8>, u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        entries.select_nth_unstable_by(n, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let top = top_words(count_words(&input), TOP_N);

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in &top {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &str) -> Vec<(String, u64)> {
        top_words(count_words(input.as_bytes()), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w).unwrap(), c))
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
        assert_eq!(got[0], ("now".to_string(), 3));
        assert_eq!(got.len(), 5);
    }

    #[test]
    fn empty() {
        assert!(run("").is_empty());
        assert!(run("123 !!").is_empty());
    }

    #[test]
    fn non_ascii_bytes_separate() {
        let counts = count_words(b"ab\xffab\xc3\xa9ab");
        assert_eq!(counts.get(b"ab".as_slice()), Some(&3));
    }
}
