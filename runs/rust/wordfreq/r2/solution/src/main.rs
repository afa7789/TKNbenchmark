//! wordfreq: print the 10 most frequent ASCII words read from standard input.

use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};

/// Maximum number of words to report.
const TOP_N: usize = 10;

/// Counts case-folded words, where a word is a maximal run of ASCII letters.
fn count_words(input: &[u8]) -> HashMap<Vec<u8>, u64> {
    let mut counts: HashMap<Vec<u8>, u64> = HashMap::new();
    let mut word = Vec::new();

    let words = input
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty());

    for raw in words {
        word.clear();
        word.extend(raw.iter().map(u8::to_ascii_lowercase));
        // Look up by slice first so repeated words don't allocate.
        match counts.get_mut(word.as_slice()) {
            Some(count) => *count += 1,
            None => {
                counts.insert(word.clone(), 1);
            }
        }
    }
    counts
}

/// Returns up to `n` entries ordered by count descending, then word ascending.
fn top_words(counts: HashMap<Vec<u8>, u64>, n: usize) -> Vec<(Vec<u8>, u64)> {
    let mut entries: Vec<(Vec<u8>, u64)> = counts.into_iter().collect();
    let order = |a: &(Vec<u8>, u64), b: &(Vec<u8>, u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0));

    if entries.len() > n && n > 0 {
        entries.select_nth_unstable_by(n - 1, order);
    }
    entries.truncate(n);
    entries.sort_unstable_by(order);
    entries
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let top = top_words(count_words(&input), TOP_N);

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in &top {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &str) -> Vec<(String, u64)> {
        top_words(count_words(input.as_bytes()), TOP_N)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w).unwrap(), c))
            .collect()
    }

    #[test]
    fn example() {
        let got = run("The cat and the hat.");
        let want = [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)];
        assert_eq!(got, want.map(|(w, c)| (w.to_string(), c)));
    }

    #[test]
    fn separators_and_non_ascii() {
        let counts = count_words(b"don't\xffstop_me 4now\xc3\xa9NOW");
        assert_eq!(counts.get(b"now".as_slice()), Some(&2));
        assert_eq!(counts.len(), 5);
    }

    #[test]
    fn empty() {
        assert!(run("").is_empty());
        assert!(run("123 !!").is_empty());
    }
}
