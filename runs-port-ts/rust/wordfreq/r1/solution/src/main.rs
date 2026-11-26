//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// Lowercases `input` in place and counts each maximal run of ASCII letters.
///
/// Every non-letter byte (including bytes >= 0x80) acts as a separator.
fn count_words(input: &mut [u8]) -> HashMap<&[u8], u64> {
    input.make_ascii_lowercase();
    let input: &[u8] = input;
    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in input
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Orders by count descending, then by word ascending in byte order.
fn compare_entries(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the top `n` entries in output order without sorting the whole map.
fn top_entries<'a>(counts: HashMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n && n > 0 {
        entries.select_nth_unstable_by(n - 1, compare_entries);
    }
    entries.truncate(n);
    entries.sort_unstable_by(compare_entries);
    entries
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = count_words(&mut input);

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_entries(counts, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("wordfreq: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &[u8]) -> Vec<(String, u64)> {
        let mut buf = input.to_vec();
        top_entries(count_words(&mut buf), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            top(b"The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators_and_high_bytes() {
        assert_eq!(
            top(b"don't\xffstop_me 4now,\xc3\x80now-NOW"),
            [("now", 3), ("don", 1), ("me", 1), ("stop", 1), ("t", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn empty() {
        assert!(top(b"").is_empty());
        assert!(top(b"123 _ '").is_empty());
    }
}
