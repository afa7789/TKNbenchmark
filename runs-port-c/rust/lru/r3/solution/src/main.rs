//! `lru` — simulate an LRU cache driven by commands on standard input.
//!
//! The first line holds the capacity; each later line is one of
//! `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`. Malformed lines
//! are ignored. The whole input is read at once and the cache borrows keys
//! and values straight from that buffer.

mod cache;

use std::io::{self, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

const MAX_CAPACITY: i64 = 1_000_000;
/// Longest key or value accepted; longer tokens make the command a no-op.
const MAX_TOKEN_LEN: usize = 255;

/// Parses the capacity line the way C's `strtol` would: optional leading
/// whitespace and sign, then as many digits as are present. The result is
/// clamped into `1..=MAX_CAPACITY`.
fn parse_capacity(line: &[u8]) -> usize {
    // The reference implementation only ever looked at the first 31 bytes.
    let line = &line[..line.len().min(31)];
    let start = line
        .iter()
        .position(|b| !matches!(b, b' ' | b'\t' | b'\n' | b'\x0b' | b'\x0c' | b'\r'))
        .unwrap_or(line.len());
    let rest = &line[start..];

    let value = match rest.split_first() {
        Some((b'-', digits)) => -digits_value(digits),
        Some((b'+', digits)) => digits_value(digits),
        _ => digits_value(rest),
    };
    value.clamp(1, MAX_CAPACITY) as usize
}

/// Value of the leading decimal digits, saturating well above the clamp range.
fn digits_value(s: &[u8]) -> i64 {
    s.iter()
        .take_while(|b| b.is_ascii_digit())
        .fold(0i64, |acc, &d| (acc * 10 + i64::from(d - b'0')).min(MAX_CAPACITY + 1))
}

/// Strips a single trailing carriage return.
fn trim_cr(line: &[u8]) -> &[u8] {
    line.strip_suffix(b"\r").unwrap_or(line)
}

fn write_line(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(bytes);
    out.push(b'\n');
}

fn run_command<'a>(cache: &mut LruCache<'a>, out: &mut Vec<u8>, line: &'a [u8]) {
    let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
    let Some(cmd) = tokens.next() else { return };

    if cmd == b"SIZE" {
        write_line(out, cache.len().to_string().as_bytes());
        return;
    }
    let Some(key) = tokens.next().filter(|k| k.len() <= MAX_TOKEN_LEN) else {
        return;
    };

    match cmd {
        b"GET" => write_line(out, cache.get(key).unwrap_or(b"NULL")),
        b"DEL" => write_line(out, if cache.remove(key) { b"1" } else { b"0" }),
        b"SET" => {
            if let Some(value) = tokens.next().filter(|v| v.len() <= MAX_TOKEN_LEN) {
                cache.set(key, value);
            }
        }
        _ => {}
    }
}

fn run(input: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    if input.is_empty() {
        return out;
    }

    let mut lines = input.split(|&b| b == b'\n').map(trim_cr);
    let capacity = parse_capacity(lines.next().unwrap_or_default());

    // Every SET occupies one line, so the remaining line count bounds the
    // number of entries the cache can ever hold.
    let remaining_lines = input.iter().filter(|&&b| b == b'\n').count();
    let mut cache = LruCache::with_capacity(capacity, remaining_lines);

    for line in lines {
        run_command(&mut cache, &mut out, line);
    }
    out
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("lru: read error: {err}");
        return ExitCode::FAILURE;
    }

    let output = run(&input);
    let mut stdout = io::stdout().lock();
    if let Err(err) = stdout.write_all(&output).and_then(|()| stdout.flush()) {
        eprintln!("lru: write error: {err}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spec_example() {
        let input = b"2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(run(input), b"1\nNULL\n2\n");
    }

    #[test]
    fn capacity_parsing_mirrors_strtol() {
        assert_eq!(parse_capacity(b"  42abc"), 42);
        assert_eq!(parse_capacity(b"+7"), 7);
        assert_eq!(parse_capacity(b"-5"), 1);
        assert_eq!(parse_capacity(b"junk"), 1);
        assert_eq!(parse_capacity(b"99999999999999999999"), 1_000_000);
    }

    #[test]
    fn tolerates_crlf_and_missing_final_newline() {
        assert_eq!(run(b"1\r\nSET a 1\r\nGET a"), b"1\n");
    }
}
