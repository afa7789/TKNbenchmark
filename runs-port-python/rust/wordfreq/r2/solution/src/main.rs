//! Print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and reported as `<count> <word>`, ordered by
//! count descending, ties broken by word ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

/// Maximum number of words to report.
const TOP_N: usize = 10;

/// Count occurrences of each lowercase word in `data`.
///
/// `data` is lowercased in place so the returned map can borrow its keys
/// directly from the buffer without per-word allocations.
fn count_words(data: &mut [u8]) -> HashMap<&[u8], u64> {
    data.make_ascii_lowercase();
    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in data
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

/// Return up to `n` `(word, count)` pairs, by count descending then word ascending.
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

    let top = top_words(count_words(&mut data), TOP_N);

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
        let mut data = input.as_bytes().to_vec();
        top_words(count_words(&mut data), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            top("The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)].map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators_and_non_ascii() {
        let mut data = b"don't stop_me 4now, now-NOW\xff\xc3(caf\xc3\xa9".to_vec();
        let counts = count_words(&mut data);
        assert_eq!(counts[&b"now"[..]], 3);
        assert_eq!(counts[&b"caf"[..]], 1);
        assert_eq!(counts.len(), 6);
    }

    #[test]
    fn empty_input() {
        assert!(top("").is_empty());
        assert!(top("123 _ !!").is_empty());
    }

    #[test]
    fn limits_to_top_n_with_ties() {
        let result = top("zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha");
        assert_eq!(result.len(), TOP_N);
        assert_eq!(result[0], ("alpha".to_string(), 2));
        assert_eq!(result[9], ("pi".to_string(), 1));
    }
}
