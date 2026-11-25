//! Word frequency counting over arbitrary bytes.
//!
//! A word is a maximal run of ASCII letters; everything else separates words.
//! Words are folded to lowercase before counting.

use std::cmp::Ordering;
use std::collections::HashMap;

/// Counts case-folded ASCII-letter words in `input`.
#[must_use]
pub fn count_words(input: &[u8]) -> HashMap<Box<[u8]>, u64> {
    let mut counts: HashMap<Box<[u8]>, u64> = HashMap::new();
    let mut word = Vec::new();

    for run in input
        .split(|b| !b.is_ascii_alphabetic())
        .filter(|run| !run.is_empty())
    {
        word.clear();
        word.extend(run.iter().map(u8::to_ascii_lowercase));
        if let Some(count) = counts.get_mut(word.as_slice()) {
            *count += 1;
        } else {
            counts.insert(word.as_slice().into(), 1);
        }
    }
    counts
}

/// Orders by count descending, then word ascending (byte order).
fn rank(a: &(Box<[u8]>, u64), b: &(Box<[u8]>, u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0))
}

/// Returns at most `n` of the `(word, count)` entries, ranked by count
/// descending, then word ascending.
#[must_use]
pub fn top_n(
    counts: impl IntoIterator<Item = (Box<[u8]>, u64)>,
    n: usize,
) -> Vec<(Box<[u8]>, u64)> {
    if n == 0 {
        return Vec::new();
    }
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        entries.select_nth_unstable_by(n - 1, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &[u8], n: usize) -> Vec<(String, u64)> {
        top_n(count_words(input), n)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.into_vec()).expect("ascii"), c))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(
            top(b"The cat and the hat.", 10),
            [("the", 2), ("and", 1), ("cat", 1), ("hat", 1)].map(|(w, c)| (w.to_owned(), c))
        );
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(
            top(b"don't\xffstop_me\xc3(4now", 10),
            [("don", 1), ("me", 1), ("now", 1), ("stop", 1), ("t", 1)]
                .map(|(w, c)| (w.to_owned(), c))
        );
    }

    #[test]
    fn empty_and_no_words() {
        assert!(top(b"", 10).is_empty());
        assert!(top(b"123 _ '\x80", 10).is_empty());
    }

    #[test]
    fn truncates_with_ties() {
        let got = top(b"d c b a a e", 3);
        assert_eq!(
            got,
            [("a", 2), ("b", 1), ("c", 1)].map(|(w, c)| (w.to_owned(), c))
        );
    }
}
