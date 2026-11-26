//! `app wordfreq`: Word frequencies: prints the 10 most frequent ASCII words of the input.
//!
//! See the `wordfreq` section of SPEC.md.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufRead, Write};

/// How many of the most frequent words are printed.
const TOP_N: usize = 10;

/// Entry point for `app wordfreq`: reads all of `input` and writes the result to `output`.
///
/// `output` is already buffered and is flushed by the caller.
pub fn run(input: impl BufRead, mut output: impl Write) -> io::Result<()> {
    let counts = count_words(input)?;
    for (word, count) in top_words(counts, TOP_N) {
        output.write_all(count.to_string().as_bytes())?;
        output.write_all(b" ")?;
        output.write_all(&word)?;
        output.write_all(b"\n")?;
    }
    Ok(())
}

/// Counts the lowercased words of `input`, streaming it chunk by chunk.
///
/// A word is a maximal run of ASCII letters; every other byte is a separator.
/// A word split across chunk boundaries is carried over in a pending buffer.
fn count_words(mut input: impl BufRead) -> io::Result<HashMap<Vec<u8>, u64>> {
    let mut counts = HashMap::new();
    let mut word = Vec::new();
    loop {
        let chunk = match input.fill_buf() {
            Ok([]) => break,
            Ok(chunk) => chunk,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(err),
        };
        for &byte in chunk {
            if byte.is_ascii_alphabetic() {
                word.push(byte.to_ascii_lowercase());
            } else if !word.is_empty() {
                record(&mut counts, &word);
                word.clear();
            }
        }
        let len = chunk.len();
        input.consume(len);
    }
    if !word.is_empty() {
        record(&mut counts, &word);
    }
    Ok(counts)
}

/// Increments the count of `word`, allocating a key only for a word not seen before.
fn record(counts: &mut HashMap<Vec<u8>, u64>, word: &[u8]) {
    match counts.get_mut(word) {
        Some(count) => *count += 1,
        None => {
            counts.insert(word.to_vec(), 1);
        }
    }
}

/// Ranking order: count descending, then word ascending (byte order).
fn rank(a: &(Vec<u8>, u64), b: &(Vec<u8>, u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0))
}

/// Returns the `n` highest-ranked `(word, count)` pairs, in ranking order.
fn top_words(counts: HashMap<Vec<u8>, u64>, n: usize) -> Vec<(Vec<u8>, u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        if n == 0 {
            return Vec::new();
        }
        entries.select_nth_unstable_by(n - 1, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wordfreq(input: &[u8]) -> String {
        let mut out = Vec::new();
        run(input, &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            wordfreq(b"The cat and the hat."),
            "2 the\n1 and\n1 cat\n1 hat\n"
        );
    }

    #[test]
    fn empty_and_wordless_input() {
        assert_eq!(wordfreq(b""), "");
        assert_eq!(wordfreq(b"123 _ ' \xff\xfe !"), "");
    }

    #[test]
    fn non_ascii_bytes_separate_words() {
        assert_eq!(wordfreq(b"ab\xc3\xa9cd AB"), "2 ab\n1 cd\n");
    }

    #[test]
    fn words_spanning_chunk_boundaries() {
        let reader = io::BufReader::with_capacity(3, &b"hello HELLO hello"[..]);
        let mut out = Vec::new();
        run(reader, &mut out).unwrap();
        assert_eq!(out, b"3 hello\n");
    }

    #[test]
    fn at_most_ten_lines_with_ties_by_word() {
        let input = "k j i h g f e d c b a a";
        assert_eq!(
            wordfreq(input.as_bytes()),
            "2 a\n1 b\n1 c\n1 d\n1 e\n1 f\n1 g\n1 h\n1 i\n1 j\n"
        );
    }
}
