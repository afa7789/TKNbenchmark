//! `wordfreq`: the ten most frequent ASCII-letter words, case-insensitive.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::{self, Write};

const TOP: usize = 10;

/// Counts words in `input` and writes the most frequent ones as `<count> <word>` lines.
pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    let lowered = input.to_ascii_lowercase();
    for (word, count) in top_words(&count_words(&lowered), TOP) {
        out.write_all(count.to_string().as_bytes())?;
        out.write_all(b" ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    Ok(())
}

type Counts<'a> = HashMap<&'a [u8], u64, BuildHasherDefault<FnvHasher>>;

/// Counts maximal runs of ASCII letters. `text` must already be lowercase.
fn count_words(text: &[u8]) -> Counts<'_> {
    let mut counts = Counts::default();
    for word in text
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Returns up to `n` entries ordered by count descending, then word ascending.
fn top_words<'a>(counts: &Counts<'a>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts.iter().map(|(&w, &c)| (w, c)).collect();
    let order = |a: &(&[u8], u64), b: &(&[u8], u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0));
    if entries.len() > n {
        entries.select_nth_unstable_by(n, order);
        entries.truncate(n);
    }
    entries.sort_unstable_by(order);
    entries
}

/// 64-bit FNV-1a: fast for the short keys counted here.
struct FnvHasher(u64);

impl Default for FnvHasher {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl Hasher for FnvHasher {
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0100_0000_01b3);
        }
    }

    fn finish(&self) -> u64 {
        self.0
    }
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
        assert_eq!(render(b"don't\xffstop_me 4now\xc3(NOW"), "2 now\n1 don\n1 me\n1 stop\n1 t\n");
    }

    #[test]
    fn empty_input() {
        assert_eq!(render(b"123 !!"), "");
    }

    #[test]
    fn at_most_ten() {
        let text = "a b c d e f g h i j k l a";
        assert_eq!(render(text.as_bytes()).lines().count(), 10);
        assert!(render(text.as_bytes()).starts_with("2 a\n1 b\n"));
    }
}
