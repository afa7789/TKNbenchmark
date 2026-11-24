//! wordfreq: print the 10 most frequent ASCII words read from standard input.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufRead, BufWriter, Write};

/// Number of entries to report.
const TOP_N: usize = 10;

/// A small, fast, non-cryptographic hasher (FxHash-style) for short byte keys.
#[derive(Default)]
struct FxHasher {
    hash: u64,
}

impl FxHasher {
    const SEED: u64 = 0x51_7c_c1_b7_27_22_0a_95;

    #[inline]
    fn add(&mut self, word: u64) {
        self.hash = (self.hash.rotate_left(5) ^ word).wrapping_mul(Self::SEED);
    }
}

impl Hasher for FxHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let mut chunks = bytes.chunks_exact(8);
        for chunk in &mut chunks {
            self.add(u64::from_le_bytes(chunk.try_into().expect("chunk of 8 bytes")));
        }
        let rest = chunks.remainder();
        if !rest.is_empty() {
            let mut buf = [0u8; 8];
            buf[..rest.len()].copy_from_slice(rest);
            self.add(u64::from_le_bytes(buf));
        }
    }

    #[inline]
    fn write_u8(&mut self, i: u8) {
        self.add(u64::from(i));
    }

    #[inline]
    fn write_usize(&mut self, i: usize) {
        self.add(i as u64);
    }

    #[inline]
    fn finish(&self) -> u64 {
        self.hash
    }
}

type Counts = HashMap<Box<[u8]>, u64, BuildHasherDefault<FxHasher>>;

/// Accumulates word counts from a byte stream that may arrive in arbitrary chunks.
#[derive(Default)]
struct WordCounter {
    counts: Counts,
    /// Lowercased bytes of a word that may continue into the next chunk.
    pending: Vec<u8>,
}

impl WordCounter {
    /// Feeds a chunk of input. Words split across chunk boundaries are handled.
    fn feed(&mut self, chunk: &[u8]) {
        let mut i = 0;
        let len = chunk.len();
        while i < len {
            if chunk[i].is_ascii_alphabetic() {
                let start = i;
                while i < len && chunk[i].is_ascii_alphabetic() {
                    i += 1;
                }
                self.pending
                    .extend(chunk[start..i].iter().map(u8::to_ascii_lowercase));
                if i < len {
                    self.flush();
                }
            } else {
                self.flush();
                i += 1;
            }
        }
    }

    /// Records the pending word, if any.
    fn flush(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        if let Some(count) = self.counts.get_mut(self.pending.as_slice()) {
            *count += 1;
        } else {
            self.counts.insert(self.pending.as_slice().into(), 1);
        }
        self.pending.clear();
    }

    /// Finishes counting and returns the `n` most frequent words, ordered by
    /// count descending, then by word ascending.
    fn top(mut self, n: usize) -> Vec<(Box<[u8]>, u64)> {
        self.flush();
        let mut entries: Vec<_> = self.counts.into_iter().collect();
        let rank = |a: &(Box<[u8]>, u64), b: &(Box<[u8]>, u64)| -> Ordering {
            b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0))
        };
        if entries.len() > n && n > 0 {
            entries.select_nth_unstable_by(n - 1, rank);
        }
        entries.truncate(n);
        entries.sort_unstable_by(rank);
        entries
    }
}

fn run() -> io::Result<()> {
    let stdin = io::stdin();
    let mut reader = io::BufReader::with_capacity(1 << 16, stdin.lock());
    let mut counter = WordCounter::default();
    loop {
        let chunk = match reader.fill_buf() {
            Ok(chunk) => chunk,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        if chunk.is_empty() {
            break;
        }
        counter.feed(chunk);
        let consumed = chunk.len();
        reader.consume(consumed);
    }

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    for (word, count) in counter.top(TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(&word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() {
    if let Err(e) = run() {
        // A closed stdout (e.g. piping into `head`) is not worth reporting.
        if e.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("wordfreq: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top_of(chunks: &[&[u8]]) -> Vec<(String, u64)> {
        let mut counter = WordCounter::default();
        for chunk in chunks {
            counter.feed(chunk);
        }
        counter
            .top(TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.into_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        let got = top_of(&[b"The cat and the hat."]);
        let want = [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)];
        assert_eq!(got, want.map(|(w, c)| (w.to_string(), c)));
    }

    #[test]
    fn words_split_across_chunks() {
        let got = top_of(&[b"hel", b"LO hello wor", b"ld"]);
        assert_eq!(got, vec![("hello".into(), 2), ("world".into(), 1)]);
    }

    #[test]
    fn non_ascii_bytes_separate() {
        let got = top_of(&[b"a\xffb\xc3\xa9a_1a"]);
        assert_eq!(got, vec![("a".into(), 3), ("b".into(), 1)]);
    }

    #[test]
    fn empty_input() {
        assert!(top_of(&[b"", b"123 ... \xff"]).is_empty());
    }
}
