//! Reads an LRU cache capacity and a command stream from stdin and writes
//! command results to stdout.

mod lru;

use std::io::{self, Read, Write};
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
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid capacity"))?;

    let mut cache = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        let Some(cmd) = tokens.next() else { continue };
        match (cmd, tokens.next(), tokens.next()) {
            (b"SET", Some(key), Some(value)) => cache.set(key, value),
            (b"GET", Some(key), _) => {
                out.write_all(cache.get(key).unwrap_or(b"NULL"))?;
                out.write_all(b"\n")?;
            }
            (b"DEL", Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (b"SIZE", _, _) => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(e) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("error reading stdin: {e}");
        return ExitCode::FAILURE;
    }
    let mut out = io::BufWriter::with_capacity(1 << 16, io::stdout().lock());
    match run(&input, &mut out) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}
