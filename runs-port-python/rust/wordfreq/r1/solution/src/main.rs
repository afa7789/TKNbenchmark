//! Print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are case-folded to lowercase and reported as `<count> <word>`,
//! ordered by count descending, then by word ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// Count case-folded words in `data`, lowercasing it in place so that the
/// returned keys can borrow from it without extra allocations.
fn count_words(data: &mut [u8]) -> HashMap<&[u8], u64> {
    data.make_ascii_lowercase();
    let data: &[u8] = data;

    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in data
        .split(|b| !b.is_ascii_lowercase())
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

/// Return up to `n` `(word, count)` pairs in ranking order.
fn top_words<'a>(counts: HashMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
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

fn run() -> io::Result<()> {
    let mut data = Vec::new();
    io::stdin().lock().read_to_end(&mut data)?;

    let counts = count_words(&mut data);
    let top = top_words(counts, TOP_N);

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
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wordfreq: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &str) -> Vec<(String, u64)> {
        let mut data = input.as_bytes().to_vec();
        top_words(count_words(&mut data), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            top("The cat and the hat."),
            vec![
                ("the".into(), 2),
                ("and".into(), 1),
                ("cat".into(), 1),
                ("hat".into(), 1)
            ]
        );
    }

    #[test]
    fn separators_and_non_ascii() {
        let mut data = b"don't stop_me 4now,\xffnow-NOW\xc3\xa9x".to_vec();
        let got = top_words(count_words(&mut data), TOP_N);
        let want: Vec<(&[u8], u64)> = vec![
            (b"now", 3),
            (b"don", 1),
            (b"me", 1),
            (b"stop", 1),
            (b"t", 1),
            (b"x", 1),
        ];
        assert_eq!(got, want);
    }

    #[test]
    fn empty_and_no_words() {
        assert!(top("").is_empty());
        assert!(top("123 _ '!").is_empty());
    }

    #[test]
    fn limits_to_ten() {
        let got = top("a b c d e f g h i j k l m a");
        assert_eq!(got.len(), TOP_N);
        assert_eq!(got[0], ("a".into(), 2));
        assert_eq!(got[9], ("j".into(), 1));
    }
}
