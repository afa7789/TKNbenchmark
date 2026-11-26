//! LRU cache simulator driven by commands on standard input.
//!
//! The whole input is read into memory up front; the cache borrows keys and
//! values straight from that buffer, so they are never copied.

mod lru;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru::LruCache;

/// Splits `input` into lines, dropping the `\n` terminator and any trailing
/// `\r`. A final line without a terminator is still yielded.
fn lines(input: &[u8]) -> impl Iterator<Item = &[u8]> {
    input.split_inclusive(|&b| b == b'\n').map(|line| {
        let line = line.strip_suffix(b"\n").unwrap_or(line);
        line.strip_suffix(b"\r").unwrap_or(line)
    })
}

/// Space-separated tokens of a line; runs of spaces count as one separator.
fn tokens(line: &[u8]) -> impl Iterator<Item = &[u8]> {
    line.split(|&b| b == b' ').filter(|t| !t.is_empty())
}

/// Parses the capacity line: a positive decimal integer (extra tokens are
/// ignored).
fn parse_capacity(line: &[u8]) -> Option<usize> {
    let tok = tokens(line).next()?;
    if tok.len() > 18 || !tok.iter().all(u8::is_ascii_digit) {
        return None;
    }
    let value = tok
        .iter()
        .fold(0usize, |acc, &d| acc * 10 + usize::from(d - b'0'));
    (value > 0).then_some(value)
}

/// Executes one command line, writing any output. Blank lines, unknown
/// commands and commands with missing arguments are ignored.
fn run_command<'a>(
    cache: &mut LruCache<'a>,
    line: &'a [u8],
    out: &mut impl Write,
) -> io::Result<()> {
    let mut toks = tokens(line);
    let Some(cmd) = toks.next() else {
        return Ok(());
    };
    match cmd {
        b"GET" => {
            if let Some(key) = toks.next() {
                let value = cache.get(key).unwrap_or(b"NULL");
                out.write_all(value)?;
                out.write_all(b"\n")?;
            }
        }
        b"SET" => {
            if let (Some(key), Some(value)) = (toks.next(), toks.next()) {
                cache.set(key, value);
            }
        }
        b"DEL" => {
            if let Some(key) = toks.next() {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
        }
        b"SIZE" => writeln!(out, "{}", cache.len())?,
        _ => {}
    }
    Ok(())
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut lines = lines(&input);
    let Some(capacity) = lines.next().and_then(parse_capacity) else {
        return Ok(()); // nothing to simulate
    };

    // Each command line inserts at most one key, so the line count bounds
    // how many entries can ever be live.
    let line_count = input.iter().filter(|&&b| b == b'\n').count() + 1;
    let mut cache = LruCache::new(capacity, line_count);

    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    for line in lines {
        run_command(&mut cache, line, &mut out)?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout is not worth reporting; just stop.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lru: {e}");
            ExitCode::FAILURE
        }
    }
}
