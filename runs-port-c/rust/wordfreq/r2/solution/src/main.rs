//! wordfreq: read stdin, print the 10 most frequent ASCII words.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Output is
//! `<count> <word>` per line, ordered by count descending, then word ascending
//! (byte order), at most [`TOP_N`] lines.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// 64-bit FNV-1a: fast and well-suited to short keys such as words.
struct Fnv1a(u64);

impl Default for Fnv1a {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for Fnv1a {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

type WordCounts<'a> = HashMap<&'a [u8], u64, BuildHasherDefault<Fnv1a>>;

/// Lowercases `text` in place and counts every maximal run of ASCII letters.
fn count_words(text: &mut [u8]) -> WordCounts<'_> {
    text.make_ascii_lowercase();
    let mut counts = WordCounts::default();
    for word in text
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Ranking order: higher count first, then lexicographically smaller word.
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the best `n` entries, sorted best-first.
fn top_words<'a>(counts: WordCounts<'a>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if n == 0 {
        return Vec::new();
    }
    if entries.len() > n {
        entries.select_nth_unstable_by(n - 1, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

fn write_report(out: &mut impl Write, top: &[(&[u8], u64)]) -> io::Result<()> {
    for &(word, count) in top {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut input) {
        // Report the failure but still summarize whatever was read.
        eprintln!("wordfreq: read error: {err}");
    }

    let top = top_words(count_words(&mut input), TOP_N);

    let mut out = BufWriter::new(io::stdout().lock());
    match write_report(&mut out, &top) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("wordfreq: write error: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &str) -> String {
        let mut bytes = input.as_bytes().to_vec();
        let top = top_words(count_words(&mut bytes), TOP_N);
        let mut out = Vec::new();
        write_report(&mut out, &top).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn example() {
        assert_eq!(run("The cat and the hat."), "2 the\n1 and\n1 cat\n1 hat\n");
    }

    #[test]
    fn separators() {
        assert_eq!(
            run("don't stop_me 4now, now-NOW"),
            "3 now\n1 don\n1 me\n1 stop\n1 t\n"
        );
    }

    #[test]
    fn empty_and_no_words() {
        assert_eq!(run(""), "");
        assert_eq!(run("123 _'!"), "");
    }

    #[test]
    fn non_ascii_bytes_separate_words() {
        let mut bytes = b"ab\xffcd\xc3(ab".to_vec();
        let top = top_words(count_words(&mut bytes), TOP_N);
        assert_eq!(top, vec![(&b"ab"[..], 2), (&b"cd"[..], 1)]);
    }

    #[test]
    fn limits_to_top_n_with_prefix_ties() {
        let input = "b a ab aa abc c d e f g h i j";
        let out = run(input);
        assert_eq!(out.lines().count(), TOP_N);
        assert!(out.starts_with("1 a\n1 aa\n1 ab\n1 abc\n1 b\n"));
    }
}
