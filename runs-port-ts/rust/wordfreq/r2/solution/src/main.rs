//! wordfreq: print the 10 most frequent words read from standard input.
//!
//! A word is a maximal run of ASCII letters; words are case-folded to lowercase.
//! Output is `<count> <word>` per line, ordered by count descending and then by
//! word ascending (byte order).

use std::cmp::Ordering;
use std::collections::HashMap;
use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

/// Count case-folded words in `data`, lowercasing the buffer in place so the
/// returned keys can borrow directly from it.
fn count_words(data: &mut [u8]) -> HashMap<&[u8], u64> {
    data.make_ascii_lowercase();
    let data: &[u8] = data;

    let mut counts: HashMap<&[u8], u64> = HashMap::new();
    for word in data
        .split(|b| !b.is_ascii_lowercase())
        .filter(|w| !w.is_empty())
    {
        *counts.entry(word).or_insert(0) += 1;
    }
    counts
}

/// Order by count descending, then word ascending.
fn rank(a: &(&[u8], u64), b: &(&[u8], u64)) -> Ordering {
    b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0))
}

/// Select the `n` best entries in rank order without sorting everything.
fn top_words<'a>(counts: HashMap<&'a [u8], u64>, n: usize) -> Vec<(&'a [u8], u64)> {
    let mut entries: Vec<_> = counts.into_iter().collect();
    if entries.len() > n {
        if n == 0 {
            return Vec::new();
        }
        entries.select_nth_unstable_by(n - 1, rank);
        entries.truncate(n);
    }
    entries.sort_unstable_by(rank);
    entries
}

fn write_report(out: &mut impl Write, top: &[(&[u8], u64)]) -> io::Result<()> {
    for (word, count) in top {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = count_words(&mut input);
    let top = top_words(counts, TOP_N);

    let mut out = BufWriter::new(io::stdout().lock());
    match write_report(&mut out, &top) {
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        other => other,
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wordfreq: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(input: &[u8]) -> String {
        let mut data = input.to_vec();
        let top = top_words(count_words(&mut data), TOP_N);
        let mut out = Vec::new();
        write_report(&mut out, &top).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn simple() {
        assert_eq!(report(b"The cat and the hat."), "2 the\n1 and\n1 cat\n1 hat\n");
    }

    #[test]
    fn separators_and_invalid_utf8() {
        assert_eq!(
            report(b"don't stop_me 4now, now-NOW\xff\xc3(now"),
            "4 now\n1 don\n1 me\n1 stop\n1 t\n"
        );
    }

    #[test]
    fn empty() {
        assert_eq!(report(b""), "");
        assert_eq!(report(b"123 \x80\xff _"), "");
    }

    #[test]
    fn top_ten_with_ties() {
        assert_eq!(
            report(b"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha"),
            "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n"
        );
    }
}
