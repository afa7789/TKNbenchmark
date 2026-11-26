//! Prints the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and reported as `<count> <word>`, ordered by
//! count descending and then by word ascending (byte order).

use std::cmp::Reverse;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

/// Number of words to report.
const TOP_N: usize = 10;

/// Counts the occurrences of each lowercase word in `text`.
///
/// `text` is lowercased in place so the returned keys can borrow from it
/// without allocating per word.
fn count_words(text: &mut [u8]) -> HashMap<&[u8], u64> {
    text.make_ascii_lowercase();
    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in text
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Returns up to `n` `(word, count)` pairs, most frequent first, ties broken
/// by word ascending.
fn top_words<'a>(counts: HashMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts.into_iter().collect();
    let key = |&(word, count): &(&'a [u8], u64)| (Reverse(count), word);
    if entries.len() > n {
        entries.select_nth_unstable_by_key(n, key);
        entries.truncate(n);
    }
    entries.sort_unstable_by_key(key);
    entries
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = count_words(&mut input);
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
    if let Err(err) = run() {
        // A closed stdout (e.g. piping into `head`) is not worth reporting.
        if err.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("wordfreq: {err}");
        }
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(text: &str) -> Vec<(String, u64)> {
        let mut bytes = text.as_bytes().to_vec();
        top_words(count_words(&mut bytes), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            top("The cat and the hat."),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn separators_and_case() {
        assert_eq!(
            top("don't stop_me 4now, now-NOW"),
            [("now", 3), ("don", 1), ("me", 1), ("stop", 1), ("t", 1)]
                .map(|(w, c)| (w.to_string(), c))
        );
    }

    #[test]
    fn non_ascii_bytes_separate_words() {
        let mut bytes = b"ab\xffcd\xc3(ab".to_vec();
        let result = top_words(count_words(&mut bytes), TOP_N);
        assert_eq!(result, vec![(&b"ab"[..], 2), (&b"cd"[..], 1)]);
    }

    #[test]
    fn empty_input() {
        assert!(top("").is_empty());
        assert!(top("123 _ '!").is_empty());
    }

    #[test]
    fn truncates_to_top_n() {
        let text = "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha";
        let result = top(text);
        assert_eq!(result.len(), TOP_N);
        assert_eq!(result[0], ("alpha".to_string(), 2));
        assert_eq!(result[9], ("pi".to_string(), 1));
    }
}
