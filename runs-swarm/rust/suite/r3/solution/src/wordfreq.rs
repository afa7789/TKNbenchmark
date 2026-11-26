//! `app wordfreq`: word frequencies. See the `wordfreq` section of SPEC.md.
//!
//! Input is streamed through the reader's buffer rather than read into memory
//! whole, so memory use is bounded by the number of distinct words, not by the
//! input size. A word may straddle two buffer refills; the partial word is
//! carried over in a small scratch buffer.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufRead, Write};

/// Number of words printed.
const TOP_N: usize = 10;

/// Entry point for `app wordfreq`: reads `input` to completion and writes the
/// result to `output`. The caller flushes `output`.
pub fn run<R: BufRead, W: Write>(input: R, mut output: W) -> io::Result<()> {
    let counts = count_words(input)?;
    for (word, count) in top_words(&counts, TOP_N) {
        output.write_all(count.to_string().as_bytes())?;
        output.write_all(b" ")?;
        output.write_all(word)?;
        output.write_all(b"\n")?;
    }
    Ok(())
}

/// Counts every word (maximal run of ASCII letters, lowercased) in `input`.
fn count_words<R: BufRead>(mut input: R) -> io::Result<HashMap<Box<[u8]>, u64>> {
    let mut counts = WordCounts::default();
    // The lowercased word currently being read; may span buffer refills.
    let mut word = Vec::new();

    loop {
        let chunk = match input.fill_buf() {
            Ok([]) => break,
            Ok(chunk) => chunk,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(err),
        };
        let len = chunk.len();

        let mut rest = chunk;
        while !rest.is_empty() {
            let run = rest
                .iter()
                .position(|b| !b.is_ascii_alphabetic())
                .unwrap_or(rest.len());
            word.extend(rest[..run].iter().map(u8::to_ascii_lowercase));
            if run == rest.len() {
                // The word may continue in the next chunk.
                break;
            }
            counts.add(&word);
            word.clear();

            let sep = rest[run..]
                .iter()
                .position(u8::is_ascii_alphabetic)
                .unwrap_or(rest.len() - run);
            rest = &rest[run + sep..];
        }

        input.consume(len);
    }
    counts.add(&word);

    Ok(counts.0)
}

/// Word counts keyed by lowercased word bytes.
#[derive(Default)]
struct WordCounts(HashMap<Box<[u8]>, u64>);

impl WordCounts {
    /// Records one occurrence of `word`; empty words are ignored. Allocates
    /// only the first time a word is seen.
    fn add(&mut self, word: &[u8]) {
        if word.is_empty() {
            return;
        }
        match self.0.get_mut(word) {
            Some(count) => *count += 1,
            None => {
                self.0.insert(word.into(), 1);
            }
        }
    }
}

/// Returns up to `n` entries of `counts`, ordered by count descending, then
/// word ascending (byte order).
fn top_words(counts: &HashMap<Box<[u8]>, u64>, n: usize) -> Vec<(&[u8], u64)> {
    fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
        b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
    }

    if n == 0 {
        return Vec::new();
    }
    let mut entries: Vec<(&[u8], u64)> =
        counts.iter().map(|(word, &count)| (&**word, count)).collect();
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
    use std::io::BufReader;

    fn wordfreq(input: &[u8]) -> String {
        let mut out = Vec::new();
        run(input, &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            wordfreq(b"The cat and the hat."),
            "2 the\n1 and\n1 cat\n1 hat\n"
        );
    }

    #[test]
    fn empty_and_wordless_input_prints_nothing() {
        assert_eq!(wordfreq(b""), "");
        assert_eq!(wordfreq(b"123 _'!? \n\t"), "");
    }

    #[test]
    fn non_letters_separate_words() {
        assert_eq!(
            wordfreq(b"don't stop_me 4now, now-NOW"),
            "3 now\n1 don\n1 me\n1 stop\n1 t\n"
        );
    }

    #[test]
    fn high_and_invalid_utf8_bytes_are_separators() {
        assert_eq!(wordfreq(b"caf\xc3\xa9\xffcaf\x80X"), "2 caf\n1 x\n");
    }

    #[test]
    fn at_most_ten_lines_with_ties_by_word() {
        let input = b"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha";
        assert_eq!(
            wordfreq(input),
            "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n"
        );
    }

    #[test]
    fn words_spanning_buffer_refills() {
        let input: &[u8] = b"abcdefgh ABCDEFGH abc.defgh";
        let mut out = Vec::new();
        run(BufReader::with_capacity(3, input), &mut out).unwrap();
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "2 abcdefgh\n1 abc\n1 defgh\n"
        );
    }
}
