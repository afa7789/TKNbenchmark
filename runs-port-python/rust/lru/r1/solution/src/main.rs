//! Simulates an LRU cache driven by commands on standard input.
//!
//! Input: the capacity on the first line, then one command per line:
//! `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`.

mod cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

/// Whitespace as understood by Python's `bytes.split()`.
fn is_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\n' | b'\r' | b'\x0b' | b'\x0c')
}

fn tokens(line: &[u8]) -> impl Iterator<Item = &[u8]> {
    line.split(|&b| is_space(b)).filter(|t| !t.is_empty())
}

fn parse_capacity(line: &[u8]) -> Option<usize> {
    let text = std::str::from_utf8(line).ok()?.trim();
    let value: i64 = text.parse().ok()?;
    // A non-positive capacity behaves like zero: every insertion is evicted at once.
    Some(usize::try_from(value).unwrap_or(0))
}

/// Executes the commands in `lines`, writing one output line per producing command.
fn run<'a, W: Write>(
    capacity: usize,
    lines: impl Iterator<Item = &'a [u8]>,
    out: &mut W,
) -> io::Result<()> {
    let mut cache: LruCache<&[u8], &[u8]> = LruCache::new(capacity);

    for line in lines {
        let mut parts = tokens(line);
        match (parts.next(), parts.next(), parts.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.put(key, value),
            (Some(b"GET"), Some(key), _) => {
                out.write_all(cache.get(key).copied().unwrap_or(b"NULL"))?;
                out.write_all(b"\n")?;
            }
            (Some(b"DEL"), Some(key), _) => {
                let answer: &[u8] = if cache.remove(key).is_some() {
                    b"1\n"
                } else {
                    b"0\n"
                };
                out.write_all(answer)?;
            }
            (Some(b"SIZE"), _, _) => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    let mut data = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut data) {
        eprintln!("error: reading standard input: {err}");
        return ExitCode::FAILURE;
    }

    let mut lines = data.split(|&b| b == b'\n');
    let first = lines.next().unwrap_or_default();
    if first.iter().all(|&b| is_space(b)) {
        return ExitCode::SUCCESS;
    }
    let Some(capacity) = parse_capacity(first) else {
        eprintln!(
            "error: invalid capacity: {:?}",
            String::from_utf8_lossy(first)
        );
        return ExitCode::FAILURE;
    };

    let stdout = io::stdout();
    let mut out = BufWriter::with_capacity(1 << 16, stdout.lock());
    match run(capacity, lines, &mut out).and_then(|()| out.flush()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: writing standard output: {err}");
            ExitCode::FAILURE
        }
    }
}
