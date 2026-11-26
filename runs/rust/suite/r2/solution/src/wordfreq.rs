//! Word frequency counting.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase; every other byte separates words.

use std::collections::HashMap;
use std::io::{self, Write};

/// How many of the most frequent words are reported.
const TOP: usize = 10;

/// Prints the most frequent words of `input` as `<count> <word>` lines.
pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    for (word, count) in top_words(&count_words(input), TOP) {
        writeln!(out, "{count} {}", String::from_utf8_lossy(word))?;
    }
    Ok(())
}

/// Counts every lowercase-folded word in `input`.
fn count_words(input: &[u8]) -> HashMap<Vec<u8>, u64> {
    let mut counts: HashMap<Vec<u8>, u64> = HashMap::new();
    let mut word = Vec::with_capacity(64);

    for run in input.split(|b| !b.is_ascii_alphabetic()) {
        if run.is_empty() {
            continue;
        }
        word.clear();
        word.extend(run.iter().map(u8::to_ascii_lowercase));
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
fn top_words(counts: &HashMap<Vec<u8>, u64>, n: usize) -> Vec<(&[u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts.iter().map(|(w, &c)| (w.as_slice(), c)).collect();
    let order = |a: &(&[u8], u64), b: &(&[u8], u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0));

    if entries.len() > n {
        entries.select_nth_unstable_by(n, order);
        entries.truncate(n);
    }
    entries.sort_unstable_by(order);
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(input: &[u8]) -> String {
        let mut out = Vec::new();
        run(input, &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        assert_eq!(render(b"The cat and the hat."), "2 the\n1 and\n1 cat\n1 hat\n");
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(render(b"don't\xffstop_me 4now, now-NOW\xc3("), "3 now\n1 don\n1 me\n1 stop\n1 t\n");
    }

    #[test]
    fn empty_and_wordless_input() {
        assert_eq!(render(b""), "");
        assert_eq!(render(b"123 ,.-_ \x80\xff"), "");
    }

    #[test]
    fn keeps_only_top_ten() {
        let text = "a b c d e f g h i j k l a";
        assert_eq!(render(text.as_bytes()).lines().count(), 10);
        assert!(render(text.as_bytes()).starts_with("2 a\n1 b\n"));
        assert!(render(text.as_bytes()).ends_with("1 j\n"));
    }
}
