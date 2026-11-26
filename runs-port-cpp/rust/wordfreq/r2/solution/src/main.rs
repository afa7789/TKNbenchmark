//! wordfreq: print the 10 most frequent ASCII words read from standard input.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, ErrorKind, Read, Write};

const TOP_N: usize = 10;
const CHUNK_SIZE: usize = 1 << 16;

type WordCounts = HashMap<Vec<u8>, u64>;

fn add_word(counts: &mut WordCounts, word: &[u8]) {
    if let Some(count) = counts.get_mut(word) {
        *count += 1;
    } else {
        counts.insert(word.to_vec(), 1);
    }
}

/// Streams `input`, accumulating lowercase words. A word may straddle chunk
/// boundaries, so the in-progress word is carried across reads.
fn count_words(mut input: impl Read) -> io::Result<WordCounts> {
    let mut counts = WordCounts::new();
    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut current = Vec::new();

    loop {
        let n = match input.read(&mut buffer) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        for &byte in &buffer[..n] {
            if byte.is_ascii_alphabetic() {
                current.push(byte.to_ascii_lowercase());
            } else if !current.is_empty() {
                add_word(&mut counts, &current);
                current.clear();
            }
        }
    }
    if !current.is_empty() {
        add_word(&mut counts, &current);
    }
    Ok(counts)
}

/// Orders by count descending, then by word ascending (byte order).
fn by_rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

fn top_words(counts: &WordCounts, limit: usize) -> Vec<(&[u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts
        .iter()
        .map(|(word, &count)| (word.as_slice(), count))
        .collect();
    if entries.len() > limit && limit > 0 {
        entries.select_nth_unstable_by(limit - 1, by_rank);
    }
    entries.truncate(limit);
    entries.sort_unstable_by(by_rank);
    entries
}

fn run() -> io::Result<()> {
    let counts = count_words(io::stdin().lock())?;
    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_words(&counts, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() {
    if let Err(e) = run() {
        eprintln!("wordfreq: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &[u8]) -> Vec<(String, u64)> {
        let counts = count_words(input).unwrap();
        top_words(&counts, TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            top(b"The cat and the hat."),
            vec![
                ("the".into(), 2),
                ("and".into(), 1),
                ("cat".into(), 1),
                ("hat".into(), 1)
            ]
        );
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(
            top(b"a\xffB\xc3(a_1a"),
            vec![("a".into(), 3), ("b".into(), 1)]
        );
    }

    #[test]
    fn empty() {
        assert!(top(b"").is_empty());
        assert!(top(b"123 _'!").is_empty());
    }
}
