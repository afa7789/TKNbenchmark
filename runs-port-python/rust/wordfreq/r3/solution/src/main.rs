//! Print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and reported as `<count> <word>`, ordered by
//! count descending with ties broken by word ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};

const TOP_N: usize = 10;
const CHUNK_SIZE: usize = 1 << 16;

/// Case-insensitive word counter fed incrementally with raw bytes.
#[derive(Debug, Default)]
struct WordCounter {
    counts: HashMap<Box<[u8]>, u64>,
    /// The (lowercased) word currently being accumulated; it may span chunks.
    current: Vec<u8>,
}

impl WordCounter {
    /// Feed a chunk of input. Words split across chunk boundaries are joined.
    fn feed(&mut self, bytes: &[u8]) {
        for &b in bytes {
            if b.is_ascii_alphabetic() {
                self.current.push(b.to_ascii_lowercase());
            } else {
                self.end_word();
            }
        }
    }

    /// Count the word in progress, if any.
    fn end_word(&mut self) {
        if self.current.is_empty() {
            return;
        }
        if let Some(count) = self.counts.get_mut(self.current.as_slice()) {
            *count += 1;
        } else {
            self.counts.insert(self.current.as_slice().into(), 1);
        }
        self.current.clear();
    }

    /// Finish the input and return the `n` most frequent words.
    fn into_top(mut self, n: usize) -> Vec<(Box<[u8]>, u64)> {
        self.end_word();
        let mut entries: Vec<_> = self.counts.into_iter().collect();
        if entries.len() > n && n > 0 {
            entries.select_nth_unstable_by(n - 1, rank);
        }
        entries.truncate(n);
        entries.sort_unstable_by(rank);
        entries
    }
}

/// Order by count descending, then word ascending.
fn rank(a: &(Box<[u8]>, u64), b: &(Box<[u8]>, u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0))
}

fn run() -> io::Result<()> {
    let mut counter = WordCounter::default();
    let mut input = io::stdin().lock();
    let mut buf = vec![0u8; CHUNK_SIZE];
    loop {
        match input.read(&mut buf) {
            Ok(0) => break,
            Ok(len) => counter.feed(&buf[..len]),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
    }

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in counter.into_top(TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(&word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() {
    if let Err(e) = run() {
        // A closed stdout (e.g. piped into `head`) is not worth reporting.
        if e.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("wordfreq: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(chunks: &[&[u8]]) -> Vec<(String, u64)> {
        let mut counter = WordCounter::default();
        for chunk in chunks {
            counter.feed(chunk);
        }
        counter
            .into_top(TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.into_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn counts_and_orders() {
        assert_eq!(
            top(&[b"The cat and the hat."]),
            [("the".into(), 2), ("and".into(), 1), ("cat".into(), 1), ("hat".into(), 1)]
        );
    }

    #[test]
    fn joins_words_across_chunks() {
        assert_eq!(top(&[b"he", b"LLO wor", b"ld"]), [("hello".into(), 1), ("world".into(), 1)]);
    }

    #[test]
    fn non_ascii_bytes_separate() {
        assert_eq!(top(&[b"a\xffb\xc3(a_1"]), [("a".into(), 2), ("b".into(), 1)]);
    }

    #[test]
    fn empty_input() {
        assert!(top(&[b"", b" 123 "]).is_empty());
    }
}
