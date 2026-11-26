//! wordfreq: print the 10 most frequent ASCII-letter words read from stdin.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, Read, Write};

const TOP_N: usize = 10;

/// Lowercases `text` in place and counts each word (maximal run of ASCII
/// letters). Keys borrow from `text`.
fn count_words(text: &mut [u8]) -> HashMap<&[u8], u64> {
    text.make_ascii_lowercase();
    let text: &[u8] = text;

    let mut counts: HashMap<&[u8], u64> = HashMap::with_capacity(1 << 12);
    for word in text
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Orders by count descending, then word ascending (byte order).
fn by_rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns the `n` highest-ranked entries, sorted by rank.
fn top_words(counts: HashMap<&[u8], u64>, n: usize) -> Vec<(&[u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        if n == 0 {
            return Vec::new();
        }
        entries.select_nth_unstable_by(n - 1, by_rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(by_rank);
    entries
}

fn main() -> io::Result<()> {
    let mut text = Vec::new();
    io::stdin().lock().read_to_end(&mut text)?;

    let top = top_words(count_words(&mut text), TOP_N);

    let mut out = Vec::new();
    for (word, count) in top {
        write!(out, "{count} ")?;
        out.extend_from_slice(word);
        out.push(b'\n');
    }
    io::stdout().lock().write_all(&out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &str) -> Vec<(String, u64)> {
        let mut text = input.as_bytes().to_vec();
        top_words(count_words(&mut text), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            run("The cat and the hat."),
            vec![
                ("the".into(), 2),
                ("and".into(), 1),
                ("cat".into(), 1),
                ("hat".into(), 1)
            ]
        );
    }

    #[test]
    fn separators_and_empty() {
        assert!(run("").is_empty());
        assert!(run("123 _' \u{e9}").is_empty());
        assert_eq!(run("don't")[0], ("don".into(), 1));
    }
}
