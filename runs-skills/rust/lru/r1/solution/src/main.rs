//! Reads a capacity and LRU cache commands from stdin, writing results to stdout.

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru::LruCache;

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input
        .split(|&b| b == b'\n')
        .map(|line| line.strip_suffix(b"\r").unwrap_or(line));

    let capacity = lines
        .next()
        .and_then(|l| std::str::from_utf8(l).ok())
        .and_then(|s| s.trim().parse::<usize>().ok())
        .filter(|&c| c > 0)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid capacity line"))?;

    let mut cache: LruCache<Box<[u8]>, Box<[u8]>> = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        match (tokens.next(), tokens.next(), tokens.next()) {
            (Some(b"SET"), Some(key), Some(value)) => cache.put(key.into(), value.into()),
            (Some(b"GET"), Some(key), _) => {
                out.write_all(cache.get(key).map_or(b"NULL", |v| v))?;
                out.write_all(b"\n")?;
            }
            (Some(b"DEL"), Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (Some(b"SIZE"), _, _) => writeln!(out, "{}", cache.len())?,
            _ => {} // Blank or unrecognised lines are ignored.
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    let result = io::stdin()
        .lock()
        .read_to_end(&mut input)
        .and_then(|_| run(&input, &mut BufWriter::with_capacity(1 << 16, io::stdout().lock())));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}
