//! wordfreq: read all of stdin and print the 10 most frequent ASCII words.
//!
//! A word is a maximal run of ASCII letters; words are case-folded to
//! lowercase. Output is `<count> <word>` per line, ordered by count
//! descending and then by word ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

/// Number of words to report.
const TOP_N: usize = 10;

/// FNV-1a hasher: fast for the short keys counted here and needs no
/// external crates. HashDoS resistance is not a concern for a CLI filter.
#[derive(Clone, Copy)]
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

type FnvBuildHasher = BuildHasherDefault<FnvHasher>;

/// Counts the words in `buf`, lowercasing its letters in place so that
/// map keys can borrow directly from the buffer.
fn count_words(buf: &mut [u8]) -> HashMap<&[u8], u64, FnvBuildHasher> {
    buf.make_ascii_lowercase();
    let buf: &[u8] = buf;

    let mut counts: HashMap<&[u8], u64, FnvBuildHasher> = HashMap::default();
    for word in buf
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Ranking order: count descending, then word ascending.
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the `limit` highest-ranked words, in rank order.
fn top_words(counts: HashMap<&[u8], u64, FnvBuildHasher>, limit: usize) -> Vec<(&[u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > limit && limit > 0 {
        entries.select_nth_unstable_by(limit - 1, rank);
    }
    entries.truncate(limit);
    entries.sort_unstable_by(rank);
    entries
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let top = top_words(count_words(&mut input), TOP_N);

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
        let mut buf = input.as_bytes().to_vec();
        top_words(count_words(&mut buf), TOP_N)
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
    fn separators() {
        assert_eq!(
            top("don't stop_me 4now, now-NOW"),
            [("now", 3), ("don", 1), ("me", 1), ("stop", 1), ("t", 1)]
                .map(|(w, c)| (w.to_owned(), c))
        );
    }

    #[test]
    fn non_ascii_bytes_separate_words() {
        let mut buf = b"ab\xffcd\xc3\xa9ab".to_vec();
        let got = top_words(count_words(&mut buf), TOP_N);
        assert_eq!(got, vec![(&b"ab"[..], 2), (&b"cd"[..], 1)]);
    }

    #[test]
    fn empty() {
        assert!(top("").is_empty());
        assert!(top("123 _ '!").is_empty());
    }
}
