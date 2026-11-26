//! lru — simulate an LRU cache driven by commands on standard input.
//!
//! The first line holds the capacity; each later line is one of
//! `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`. The whole input is
//! read up front so keys and values can borrow from it without copying.

mod lru;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru::LruCache;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lru: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout().lock();
    let mut out = BufWriter::with_capacity(1 << 16, stdout);
    execute(&input, &mut out)?;
    out.flush()
}

/// Runs every command in `input`, writing results to `out`.
fn execute(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n').map(strip_cr);
    let capacity = lines.next().map_or(1, parse_capacity);
    let mut cache = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        let Some(command) = tokens.next() else {
            continue;
        };
        let mut arg = || tokens.next().unwrap_or_default();

        match command {
            b"SET" => {
                let key = arg();
                let value = arg();
                if !key.is_empty() {
                    cache.set(key, value);
                }
            }
            b"GET" => {
                let value = cache.get(arg()).unwrap_or(b"NULL");
                out.write_all(value)?;
                out.write_all(b"\n")?;
            }
            b"DEL" => {
                out.write_all(if cache.remove(arg()) { b"1\n" } else { b"0\n" })?;
            }
            b"SIZE" => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    Ok(())
}

fn strip_cr(line: &[u8]) -> &[u8] {
    line.strip_suffix(b"\r").unwrap_or(line)
}

/// Parses the capacity line leniently: leading blanks are skipped, parsing
/// stops at the first non-digit, the value saturates at `u32::MAX`, and
/// anything below 1 becomes 1.
fn parse_capacity(line: &[u8]) -> usize {
    let value = line
        .iter()
        .skip_while(|&&b| b == b' ' || b == b'\t')
        .take_while(|b| b.is_ascii_digit())
        .fold(0u32, |acc, &d| acc.saturating_mul(10).saturating_add(u32::from(d - b'0')));
    usize::try_from(value.max(1)).unwrap_or(usize::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_str(input: &str) -> String {
        let mut out = Vec::new();
        execute(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(run_str(input), "1\nNULL\n2\n");
    }

    #[test]
    fn handles_crlf_and_missing_final_newline() {
        assert_eq!(run_str("1\r\nSET a 1\r\nGET a"), "1\n");
    }

    #[test]
    fn capacity_parsing() {
        assert_eq!(parse_capacity(b" 42"), 42);
        assert_eq!(parse_capacity(b"0"), 1);
        assert_eq!(parse_capacity(b"99999999999"), u32::MAX as usize);
    }
}
