//! Simulates an LRU cache driven by commands read from standard input.
//!
//! The first line holds the capacity; each later line is one of
//! `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`.

mod lru;

use std::io::{self, Read, Write};

use lru::LruCache;

/// Whitespace as understood by Python's `bytes.split()`.
fn is_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

fn trim(mut s: &[u8]) -> &[u8] {
    while let [first, rest @ ..] = s
        && is_space(*first)
    {
        s = rest;
    }
    while let [rest @ .., last] = s
        && is_space(*last)
    {
        s = rest;
    }
    s
}

/// Parses the capacity line with the leniency of Python's `int()`:
/// surrounding whitespace, an optional sign and single underscores between
/// digits are accepted. A negative capacity behaves like zero, and values too
/// large to represent saturate.
fn parse_capacity(line: &[u8]) -> Option<usize> {
    let s = trim(line);
    let (negative, digits) = match s {
        [b'-', rest @ ..] => (true, rest),
        [b'+', rest @ ..] => (false, rest),
        _ => (false, s),
    };
    if digits.is_empty() || digits[0] == b'_' || digits[digits.len() - 1] == b'_' {
        return None;
    }

    let mut value: usize = 0;
    let mut prev_underscore = false;
    for &b in digits {
        match b {
            b'0'..=b'9' => {
                value = value.saturating_mul(10).saturating_add(usize::from(b - b'0'));
                prev_underscore = false;
            }
            b'_' if !prev_underscore => prev_underscore = true,
            _ => return None,
        }
    }
    Some(if negative { 0 } else { value })
}

/// Executes every command in `input`, returning the produced output.
fn run(input: &[u8]) -> Vec<u8> {
    let mut lines = input.split(|&b| b == b'\n');
    let Some(capacity) = lines.next().and_then(parse_capacity) else {
        return Vec::new();
    };

    let mut cache = LruCache::new(capacity);
    let mut out = Vec::new();

    for line in lines {
        let mut tokens = line.split(|&b| is_space(b)).filter(|t| !t.is_empty());
        let Some(cmd) = tokens.next() else {
            continue;
        };
        match cmd {
            b"GET" => {
                if let Some(key) = tokens.next() {
                    out.extend_from_slice(cache.get(key).unwrap_or(b"NULL"));
                    out.push(b'\n');
                }
            }
            b"SET" => {
                if let (Some(key), Some(value)) = (tokens.next(), tokens.next()) {
                    cache.set(key, value);
                }
            }
            b"DEL" => {
                if let Some(key) = tokens.next() {
                    out.extend_from_slice(if cache.remove(key) { b"1\n" } else { b"0\n" });
                }
            }
            b"SIZE" => {
                // Writing into a Vec cannot fail.
                let _ = writeln!(out, "{}", cache.len());
            }
            _ => {}
        }
    }
    out
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let output = run(&input);
    let mut stdout = io::stdout().lock();
    stdout.write_all(&output)?;
    stdout.flush()
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
    fn last_line_without_newline() {
        assert_eq!(run(b"1\nSET a 1\nGET a"), b"1\n");
    }

    #[test]
    fn capacity_parsing() {
        assert_eq!(parse_capacity(b" 1_000\r"), Some(1000));
        assert_eq!(parse_capacity(b"-3"), Some(0));
        assert_eq!(parse_capacity(b"1__0"), None);
        assert_eq!(parse_capacity(b"abc"), None);
        assert_eq!(parse_capacity(b""), None);
    }

    #[test]
    fn invalid_capacity_produces_no_output() {
        assert_eq!(run(b"x\nSIZE\n"), b"");
    }
}
