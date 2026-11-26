//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and ranked by count descending, then by word
//! ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// Counts lowercase-folded words in `text`, folding the buffer in place so
/// the map can borrow word slices directly instead of allocating per word.
fn count_words(text: &mut [u8]) -> HashMap<&[u8], u64> {
    text.make_ascii_lowercase();
    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in text
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Ranking order: count descending, then word ascending (byte order).
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Selects the top `n` entries in rank order without sorting every entry.
fn top_words<'a>(counts: HashMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
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
        let mut buf = b"don't stop_me 4now, now-NOW\xffx\xc3(x".to_vec();
        let got = top_words(count_words(&mut buf), TOP_N);
        assert_eq!(
            got,
            vec![
                (&b"now"[..], 3),
                (&b"x"[..], 2),
                (&b"don"[..], 1),
                (&b"me"[..], 1),
                (&b"stop"[..], 1),
                (&b"t"[..], 1)
            ]
        );
    }

    #[test]
    fn empty() {
        assert!(top("").is_empty());
        assert!(top("123 _ ' !").is_empty());
    }

    #[test]
    fn limits_to_ten() {
        let got = top("zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha");
        assert_eq!(got.len(), 10);
        assert_eq!(got[0], ("alpha".into(), 2));
        assert_eq!(got[9], ("pi".into(), 1));
    }
}
