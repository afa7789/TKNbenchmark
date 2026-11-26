//! LRU cache simulator: reads a capacity and a stream of commands from
//! standard input and writes command results to standard output.

mod lru;

use std::io::{self, BufWriter, Read, Write};

use lru::LruCache;

/// A command token; `None` when the token is missing from the line.
type Token = Option<Box<[u8]>>;

/// Parses a leading decimal integer the way `parseInt(s, 10)` does:
/// optional leading whitespace and sign, then digits; trailing text is ignored.
fn parse_capacity(line: &[u8]) -> usize {
    let digits = line.trim_ascii_start();
    let digits = digits.strip_prefix(b"+").unwrap_or(digits);
    digits
        .iter()
        .take_while(|b| b.is_ascii_digit())
        .fold(0usize, |acc, &b| {
            acc.saturating_mul(10).saturating_add(usize::from(b - b'0'))
        })
}

fn token(part: Option<&[u8]>) -> Token {
    part.map(Box::from)
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n');
    let capacity = parse_capacity(lines.next().unwrap_or_default());
    let mut cache: LruCache<Token, Token> = LruCache::new(capacity);

    for line in lines {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            continue;
        }

        let mut parts = line.split(|&b| b == b' ');
        match parts.next().unwrap_or_default() {
            b"SET" => {
                let key = token(parts.next());
                let value = token(parts.next());
                cache.set(key, value);
            }
            b"GET" => {
                let key = token(parts.next());
                match cache.get(&key) {
                    Some(Some(value)) => out.write_all(value)?,
                    _ => out.write_all(b"NULL")?,
                }
                out.write_all(b"\n")?;
            }
            b"DEL" => {
                let key = token(parts.next());
                out.write_all(if cache.remove(&key) { b"1\n" } else { b"0\n" })?;
            }
            b"SIZE" => writeln!(out, "{}", cache.len())?,
            _ => {} // ignore unknown commands
        }
    }

    out.flush()
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    run(&input, &mut out)
}
