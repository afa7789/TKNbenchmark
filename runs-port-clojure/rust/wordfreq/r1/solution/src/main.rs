//! Prints the ten most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and reported as `<count> <word>`, ordered by
//! count descending and then by word ascending.

use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

/// Number of words to report.
const TOP_N: usize = 10;

/// Counts the lowercased words in `input`.
fn count_words(input: &[u8]) -> HashMap<Vec<u8>, u64> {
    let mut counts: HashMap<Vec<u8>, u64> = HashMap::new();
    let mut word = Vec::new();

    let mut flush = |word: &mut Vec<u8>| {
        if word.is_empty() {
            return;
        }
        match counts.get_mut(word.as_slice()) {
            Some(count) => *count += 1,
            None => {
                counts.insert(word.clone(), 1);
            }
        }
        word.clear();
    };

    for &byte in input {
        if byte.is_ascii_alphabetic() {
            word.push(byte.to_ascii_lowercase());
        } else {
            flush(&mut word);
        }
    }
    flush(&mut word);

    counts
}

/// Returns up to `n` `(word, count)` pairs ordered by count descending, then
/// word ascending.
fn top_words(input: &[u8], n: usize) -> Vec<(Vec<u8>, u64)> {
    let mut entries: Vec<(Vec<u8>, u64)> = count_words(input).into_iter().collect();
    let by_frequency =
        |a: &(Vec<u8>, u64), b: &(Vec<u8>, u64)| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0));

    if entries.len() > n && n > 0 {
        entries.select_nth_unstable_by(n - 1, by_frequency);
    }
    entries.truncate(n);
    entries.sort_unstable_by(by_frequency);
    entries
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_words(&input, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(&word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("wordfreq: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(input: &[u8]) -> String {
        top_words(input, TOP_N)
            .into_iter()
            .map(|(w, c)| format!("{c} {}\n", String::from_utf8(w).unwrap()))
            .collect()
    }

    #[test]
    fn example() {
        assert_eq!(render(b"The cat and the hat."), "2 the\n1 and\n1 cat\n1 hat\n");
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(
            render(b"don't stop_me 4now, now-NOW\xff\xc3(x"),
            "3 now\n1 don\n1 me\n1 stop\n1 t\n1 x\n"
        );
    }

    #[test]
    fn empty() {
        assert_eq!(render(b""), "");
        assert_eq!(render(b"123 !!"), "");
    }

    #[test]
    fn limits_to_ten() {
        let input = b"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha";
        assert_eq!(
            render(input),
            "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n"
        );
    }
}
