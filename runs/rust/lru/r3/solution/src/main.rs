//! Simulates an LRU cache driven by commands on standard input.

mod lru;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru::LruCache;

type Bytes = Box<[u8]>;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut lines = input
        .split(|&b| b == b'\n')
        .map(|l| l.strip_suffix(b"\r").unwrap_or(l));

    let capacity = lines
        .next()
        .and_then(|l| std::str::from_utf8(l).ok())
        .and_then(|s| s.trim().parse::<usize>().ok())
        .filter(|&c| c > 0)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid capacity"))?;

    let stdout = io::stdout();
    let mut out = BufWriter::with_capacity(1 << 16, stdout.lock());
    let mut cache: LruCache<Bytes, Bytes> = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        match (tokens.next(), tokens.next(), tokens.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.put(key.into(), value.into()),
            (Some(b"GET"), Some(key), _) => match cache.get(key) {
                Some(value) => {
                    out.write_all(value)?;
                    out.write_all(b"\n")?;
                }
                None => out.write_all(b"NULL\n")?,
            },
            (Some(b"DEL"), Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), _, _) => writeln!(out, "{}", cache.len())?,
            // Blank or malformed lines are ignored.
            _ => {}
        }
    }

    out.flush()
}
