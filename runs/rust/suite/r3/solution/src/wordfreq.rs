//! `wordfreq`: print the ten most frequent words of the input.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase; every other
//! byte is a separator.

use std::io::{self, Write};

use crate::fxhash::FxHashMap;

const TOP: usize = 10;

pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    for (word, count) in top_words(input, TOP) {
        out.write_all(count.to_string().as_bytes())?;
        out.write_all(b" ")?;
        out.write_all(&word)?;
        out.write_all(b"\n")?;
    }
    Ok(())
}

/// Counts every word in `input` (lowercased).
fn count_words(input: &[u8]) -> FxHashMap<Box<[u8]>, u64> {
    let mut counts: FxHashMap<Box<[u8]>, u64> = FxHashMap::default();
    let mut word = Vec::with_capacity(64);
    let mut rest = input;

    while let Some(start) = rest.iter().position(u8::is_ascii_alphabetic) {
        rest = &rest[start..];
        let len = rest
            .iter()
            .position(|b| !b.is_ascii_alphabetic())
            .unwrap_or(rest.len());
        let (raw, tail) = rest.split_at(len);
        rest = tail;

        word.clear();
        word.extend(raw.iter().map(u8::to_ascii_lowercase));
        // Look up by slice first so that repeated words never allocate.
        match counts.get_mut(word.as_slice()) {
            Some(count) => *count += 1,
            None => {
                counts.insert(word.as_slice().into(), 1);
            }
        }
    }
    counts
}

/// The `n` most frequent words, by count descending then word ascending.
fn top_words(input: &[u8], n: usize) -> Vec<(Box<[u8]>, u64)> {
    let mut entries: Vec<_> = count_words(input).into_iter().collect();
    let order =
        |a: &(Box<[u8]>, u64), b: &(Box<[u8]>, u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0));
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
        assert_eq!(
            render(b"The cat and the hat."),
            "2 the\n1 and\n1 cat\n1 hat\n"
        );
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(
            render(b"don't\xffstop_me 4now,\xc3(now-NOW"),
            "3 now\n1 don\n1 me\n1 stop\n1 t\n"
        );
    }

    #[test]
    fn empty_and_no_words() {
        assert_eq!(render(b""), "");
        assert_eq!(render(b"123 _ !!"), "");
    }

    #[test]
    fn at_most_ten_with_ties() {
        let input = b"l k j i h g f e d c b a a";
        assert_eq!(
            render(input),
            "2 a\n1 b\n1 c\n1 d\n1 e\n1 f\n1 g\n1 h\n1 i\n1 j\n"
        );
    }
}
