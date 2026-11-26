//! Word-frequency counting over arbitrary byte streams.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase before counting.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, Read};

/// Size of the chunks read from the input stream.
const BUFFER_SIZE: usize = 64 * 1024;

/// Accumulates case-insensitive word counts from byte chunks.
///
/// Words may span chunk boundaries; call [`WordCounter::finish`] once all input
/// has been fed to account for a trailing word.
#[derive(Debug, Default)]
pub struct WordCounter {
    counts: HashMap<Box<[u8]>, u64>,
    pending: Vec<u8>,
}

impl WordCounter {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feeds a chunk of input bytes.
    pub fn feed(&mut self, chunk: &[u8]) {
        let mut rest = chunk;
        while let Some(end) = rest.iter().position(|b| !b.is_ascii_alphabetic()) {
            let (letters, tail) = rest.split_at(end);
            self.pending
                .extend(letters.iter().map(u8::to_ascii_lowercase));
            self.flush_pending();

            let next = tail
                .iter()
                .position(u8::is_ascii_alphabetic)
                .unwrap_or(tail.len());
            rest = &tail[next..];
        }
        // Whatever remains is a run of letters that may continue in the next chunk.
        self.pending.extend(rest.iter().map(u8::to_ascii_lowercase));
    }

    /// Flushes any trailing word and returns the final counts.
    pub fn finish(mut self) -> HashMap<Box<[u8]>, u64> {
        self.flush_pending();
        self.counts
    }

    /// Records the word accumulated in `pending`, if any, and clears it.
    fn flush_pending(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        if let Some(count) = self.counts.get_mut(self.pending.as_slice()) {
            *count += 1;
        } else {
            self.counts.insert(self.pending.as_slice().into(), 1);
        }
        self.pending.clear();
    }
}

/// Counts the words in everything readable from `reader`.
pub fn count_words<R: Read>(mut reader: R) -> io::Result<HashMap<Box<[u8]>, u64>> {
    let mut counter = WordCounter::new();
    let mut buf = vec![0u8; BUFFER_SIZE];
    loop {
        match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => counter.feed(&buf[..n]),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(e),
        }
    }
    Ok(counter.finish())
}

/// Orders by count descending, then word ascending (byte order).
fn by_count_then_word(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Returns up to `n` `(word, count)` pairs, most frequent first.
pub fn top_words(counts: &HashMap<Box<[u8]>, u64>, n: usize) -> Vec<(&[u8], u64)> {
    let mut entries: Vec<(&[u8], u64)> = counts.iter().map(|(w, &c)| (&**w, c)).collect();
    if n == 0 {
        return Vec::new();
    }
    if entries.len() > n {
        entries.select_nth_unstable_by(n - 1, by_count_then_word);
        entries.truncate(n);
    }
    entries.sort_unstable_by(by_count_then_word);
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    fn top(input: &[u8], n: usize) -> Vec<(String, u64)> {
        let counts = count_words(input).unwrap();
        top_words(&counts, n)
            .into_iter()
            .map(|(w, c)| (String::from_utf8(w.to_vec()).unwrap(), c))
            .collect()
    }

    fn pairs(expected: &[(&str, u64)]) -> Vec<(String, u64)> {
        expected.iter().map(|&(w, c)| (w.to_owned(), c)).collect()
    }

    #[test]
    fn counts_and_orders() {
        assert_eq!(
            top(b"The cat and the hat.", 10),
            pairs(&[("the", 2), ("and", 1), ("cat", 1), ("hat", 1)])
        );
    }

    #[test]
    fn separators_split_words() {
        assert_eq!(
            top(b"don't stop_me 4now, now-NOW\xff\xc3(x", 10),
            pairs(&[
                ("now", 3),
                ("don", 1),
                ("me", 1),
                ("stop", 1),
                ("t", 1),
                ("x", 1)
            ])
        );
    }

    #[test]
    fn empty_input() {
        assert!(top(b"", 10).is_empty());
        assert!(top(b" 123 ,.\x80", 10).is_empty());
    }

    #[test]
    fn words_across_chunks() {
        let mut counter = WordCounter::new();
        for chunk in [&b"he"[..], b"LL", b"o wor", b"ld hel", b"lo"] {
            counter.feed(chunk);
        }
        let counts = counter.finish();
        assert_eq!(counts.get(&b"hello"[..]), Some(&2));
        assert_eq!(counts.get(&b"world"[..]), Some(&1));
    }

    #[test]
    fn long_words() {
        let word = "a".repeat(200);
        let input = format!("{word} {} {word}", word.to_uppercase());
        assert_eq!(top(input.as_bytes(), 10), vec![(word, 3)]);
    }

    #[test]
    fn limits_to_n() {
        let result = top(b"b a c b d e f g h i j k l", 3);
        assert_eq!(result, pairs(&[("b", 2), ("a", 1), ("c", 1)]));
    }
}
