//! Reads an LRU capacity and a stream of cache commands from stdin and writes
//! the command results to stdout.

mod lru;

use std::io::{self, BufWriter, Read, Write};

use lru::LruCache;

type Bytes = Box<[u8]>;

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

    let mut cache: LruCache<Bytes, Bytes> = LruCache::new(capacity);

    for line in lines {
        let mut tokens = line.split(|&b| b == b' ').filter(|t| !t.is_empty());
        let Some(cmd) = tokens.next() else { continue };
        match (cmd, tokens.next(), tokens.next()) {
            (b"SET", Some(key), Some(value)) => cache.set(key.into(), value.into()),
            (b"GET", Some(key), _) => match cache.get(key) {
                Some(value) => {
                    out.write_all(value)?;
                    out.write_all(b"\n")?;
                }
                None => out.write_all(b"NULL\n")?,
            },
            (b"DEL", Some(key), _) => {
                out.write_all(if cache.remove(key) { b"1\n" } else { b"0\n" })?;
            }
            (b"SIZE", _, _) => writeln!(out, "{}", cache.len())?,
            _ => {}
        }
    }
    Ok(())
}

fn main() {
    let mut input = Vec::new();
    if let Err(e) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("error reading stdin: {e}");
        std::process::exit(1);
    }
    let stdout = io::stdout();
    let mut out = BufWriter::with_capacity(1 << 16, stdout.lock());
    if let Err(e) = run(&input, &mut out).and_then(|()| out.flush()) {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}
