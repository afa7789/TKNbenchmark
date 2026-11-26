//! LRU cache simulator: reads a capacity and a stream of commands from stdin.

mod lru;

use std::io::{self, Read, Write};

use lru::LruCache;

/// Strips trailing `\r`, spaces and tabs, and leading spaces and tabs.
fn trim(line: &[u8]) -> &[u8] {
    let end = line
        .iter()
        .rposition(|&b| !matches!(b, b'\r' | b' ' | b'\t'))
        .map_or(0, |i| i + 1);
    let line = &line[..end];
    let start = line
        .iter()
        .position(|&b| !matches!(b, b' ' | b'\t'))
        .unwrap_or(line.len());
    &line[start..]
}

/// Splits off the next space-separated token, advancing `rest` past it.
fn next_token<'a>(rest: &mut &'a [u8]) -> &'a [u8] {
    match rest.iter().position(|&b| b == b' ') {
        Some(pos) => {
            let tok = &rest[..pos];
            *rest = &rest[pos + 1..];
            tok
        }
        None => std::mem::take(rest),
    }
}

/// Parses the leading decimal digits of `s`; yields 0 if there are none or
/// the value overflows.
fn parse_capacity(s: &[u8]) -> usize {
    s.iter()
        .take_while(|b| b.is_ascii_digit())
        .try_fold(0usize, |acc, &b| {
            acc.checked_mul(10)?.checked_add(usize::from(b - b'0'))
        })
        .unwrap_or(0)
}

fn run(input: &[u8], out: &mut Vec<u8>) {
    if input.is_empty() {
        return;
    }
    let mut lines = input
        .strip_suffix(b"\n")
        .unwrap_or(input)
        .split(|&b| b == b'\n')
        .map(trim);

    let capacity = lines.next().map_or(0, parse_capacity);
    let mut cache = LruCache::new(capacity);

    for line in lines {
        let mut args = line;
        match next_token(&mut args) {
            b"SET" => {
                let key = next_token(&mut args);
                let value = next_token(&mut args);
                cache.set(key, value);
            }
            b"GET" => {
                let value = cache.get(next_token(&mut args));
                out.extend_from_slice(value.unwrap_or(b"NULL"));
                out.push(b'\n');
            }
            b"DEL" => {
                let removed = cache.remove(next_token(&mut args));
                out.extend_from_slice(if removed { b"1\n" } else { b"0\n" });
            }
            b"SIZE" => {
                out.extend_from_slice(cache.len().to_string().as_bytes());
                out.push(b'\n');
            }
            _ => {}
        }
    }
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = Vec::with_capacity(1 << 16);
    run(&input, &mut out);

    let mut stdout = io::stdout().lock();
    stdout.write_all(&out)?;
    stdout.flush()
}
