//! Simulates an LRU cache driven by commands read from standard input.
//!
//! The first line holds the capacity; each later line is one of
//! `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`.

mod lru;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru::LruCache;

const NULL: &[u8] = b"NULL";

/// Whitespace as understood by Python's `bytes.split()`.
fn is_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

fn tokens(line: &[u8]) -> impl Iterator<Item = &[u8]> {
    line.split(|&b| is_space(b)).filter(|t| !t.is_empty())
}

fn parse_capacity(line: &[u8]) -> Option<usize> {
    let text = std::str::from_utf8(line).ok()?.trim();
    text.parse().ok().filter(|&c| c > 0)
}

/// Executes the command stream in `input`, writing results to `out`.
fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n');
    let Some(capacity) = lines.next().and_then(parse_capacity) else {
        return Ok(());
    };

    let mut cache: LruCache<&[u8], &[u8]> = LruCache::new(capacity);

    for line in lines {
        let mut parts = tokens(line);
        let Some(cmd) = parts.next() else { continue };
        match (cmd, parts.next(), parts.next()) {
            (b"GET", Some(key), _) => {
                out.write_all(cache.get(&key).copied().unwrap_or(NULL))?;
                out.write_all(b"\n")?;
            }
            (b"SET", Some(key), Some(value)) => cache.put(key, value),
            (b"DEL", Some(key), _) => {
                out.write_all(if cache.remove(&key) { b"1\n" } else { b"0\n" })?;
            }
            (b"SIZE", _, _) => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("lru: failed to read stdin: {err}");
        return ExitCode::FAILURE;
    }
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    match run(&input, &mut out).and_then(|()| out.flush()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lru: failed to write output: {err}");
            ExitCode::FAILURE
        }
    }
}
