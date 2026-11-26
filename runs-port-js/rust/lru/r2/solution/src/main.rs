//! LRU cache simulator: reads a capacity and a list of commands from stdin
//! and writes the results of `GET`, `DEL` and `SIZE` to stdout.

mod cache;

use std::io::{self, Read, Write};

use cache::LruCache;

/// Parses the leading decimal integer of `line`, ignoring surrounding
/// whitespace and any trailing garbage.
fn parse_capacity(line: &[u8]) -> Option<usize> {
    let line = line.trim_ascii();
    let digits = line.iter().take_while(|b| b.is_ascii_digit()).count();
    std::str::from_utf8(&line[..digits]).ok()?.parse().ok()
}

/// Splits `s` at the first space into `(head, rest)`; `rest` is empty if
/// there is no space.
fn split_token(s: &[u8]) -> (&[u8], &[u8]) {
    match s.iter().position(|&b| b == b' ') {
        Some(i) => (&s[..i], &s[i + 1..]),
        None => (s, &[]),
    }
}

fn run(input: &[u8], out: &mut Vec<u8>) {
    let mut lines = input.split(|&b| b == b'\n');
    let capacity = lines
        .next()
        .and_then(parse_capacity)
        .filter(|&c| c > 0)
        .unwrap_or(1);
    let mut cache = LruCache::new(capacity);

    for line in lines {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            continue;
        }
        let (cmd, args) = split_token(line);
        match cmd {
            b"SET" => {
                let (key, value) = split_token(args);
                cache.set(key, value);
            }
            b"GET" => {
                out.extend_from_slice(cache.get(args).unwrap_or(b"NULL"));
                out.push(b'\n');
            }
            b"DEL" => {
                out.extend_from_slice(if cache.remove(args) { b"1\n" } else { b"0\n" });
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
    let mut out = Vec::with_capacity(input.len() / 2);
    run(&input, &mut out);
    let mut stdout = io::stdout().lock();
    stdout.write_all(&out)?;
    stdout.flush()
}
