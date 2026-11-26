//! LRU cache simulator: reads a capacity and a stream of commands from stdin.

mod lru;

use std::io::{self, Read, Write};

use lru::LruCache;

/// Parses the leading decimal digits of `s`, ignoring anything after them.
fn parse_capacity(s: &[u8]) -> usize {
    s.iter()
        .take_while(|b| b.is_ascii_digit())
        .fold(0usize, |acc, &b| {
            acc.saturating_mul(10).saturating_add(usize::from(b - b'0'))
        })
}

/// Splits off the next space-delimited token from `rest`.
fn next_token<'a>(rest: &mut &'a [u8]) -> &'a [u8] {
    match rest.iter().position(|&b| b == b' ') {
        Some(pos) => {
            let token = &rest[..pos];
            *rest = &rest[pos + 1..];
            token
        }
        None => std::mem::take(rest),
    }
}

fn run(input: &[u8], out: &mut Vec<u8>) {
    let data = input.strip_suffix(b"\n").unwrap_or(input);
    let mut lines = data
        .split(|&b| b == b'\n')
        .map(|line| line.strip_suffix(b"\r").unwrap_or(line));

    let Some(first) = lines.next() else { return };
    let mut cache = LruCache::new(parse_capacity(first));

    for line in lines {
        let mut rest = line;
        match next_token(&mut rest) {
            b"SET" => {
                let key = next_token(&mut rest);
                let value = next_token(&mut rest);
                cache.set(key, value);
            }
            b"GET" => {
                let value = cache.get(next_token(&mut rest));
                out.extend_from_slice(value.unwrap_or(b"NULL"));
                out.push(b'\n');
            }
            b"DEL" => {
                let removed = cache.remove(next_token(&mut rest));
                out.extend_from_slice(if removed { b"1\n" } else { b"0\n" });
            }
            b"SIZE" => {
                // Writing to a Vec cannot fail.
                let _ = writeln!(out, "{}", cache.len());
            }
            _ => {}
        }
    }
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = Vec::with_capacity(1 << 20);
    run(&input, &mut out);

    let mut stdout = io::stdout().lock();
    stdout.write_all(&out)?;
    stdout.flush()
}
