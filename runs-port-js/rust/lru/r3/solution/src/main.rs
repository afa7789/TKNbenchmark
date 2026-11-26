//! LRU cache simulator: reads a capacity and commands from stdin and
//! writes command results to stdout. See SPEC.md.

mod lru;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru::LruCache;

/// Parses a leading base-10 integer, ignoring surrounding whitespace.
fn parse_capacity(line: &[u8]) -> Option<usize> {
    let s = std::str::from_utf8(line).ok()?.trim();
    let digits = s.bytes().take_while(u8::is_ascii_digit).count();
    s[..digits].parse().ok()
}

/// Splits off the first space-separated token, returning it and the rest.
fn split_token(s: &[u8]) -> (&[u8], Option<&[u8]>) {
    match s.iter().position(|&b| b == b' ') {
        Some(i) => (&s[..i], Some(&s[i + 1..])),
        None => (s, None),
    }
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n');
    let capacity = lines.next().and_then(parse_capacity).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "first line must be the capacity",
        )
    })?;
    let mut cache: LruCache<Box<[u8]>, Box<[u8]>> = LruCache::new(capacity);

    for line in lines {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            continue;
        }
        match split_token(line) {
            (b"SET", Some(args)) => {
                if let (key, Some(value)) = split_token(args) {
                    cache.set(key.into(), value.into());
                }
            }
            (b"GET", Some(key)) => {
                match cache.get(key) {
                    Some(value) => out.write_all(value)?,
                    None => out.write_all(b"NULL")?,
                }
                out.write_all(b"\n")?;
            }
            (b"DEL", Some(key)) => {
                let removed = cache.remove(key);
                out.write_all(if removed { b"1\n" } else { b"0\n" })?;
            }
            (b"SIZE", None) => writeln!(out, "{}", cache.len())?,
            _ => {} // ignore unknown or malformed commands
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    let result = io::stdin().lock().read_to_end(&mut input).and_then(|_| {
        run(
            &input,
            &mut BufWriter::with_capacity(1 << 16, io::stdout().lock()),
        )
    });
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lru: {err}");
            ExitCode::FAILURE
        }
    }
}
