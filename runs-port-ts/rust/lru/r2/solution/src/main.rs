//! Reads an LRU cache simulation from stdin and writes command results to stdout.

mod lru;

use std::io::{self, BufWriter, Read, Write};

use lru::LruCache;

/// Parses the leading integer of `line` the way JavaScript's `parseInt` does:
/// optional leading whitespace, an optional sign, then decimal digits; any
/// trailing text is ignored. Returns `None` when no digits are present.
fn parse_leading_int(line: &[u8]) -> Option<i128> {
    let s = line.trim_ascii_start();
    let (negative, rest) = match s.first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    let digits = rest.iter().take_while(|b| b.is_ascii_digit()).count();
    if digits == 0 {
        return None;
    }
    let magnitude = rest[..digits].iter().fold(0i128, |acc, &d| {
        acc.saturating_mul(10).saturating_add(i128::from(d - b'0'))
    });
    Some(if negative { -magnitude } else { magnitude })
}

/// Splits `line` at the first space into `(command, rest)`.
fn split_command(line: &[u8]) -> (&[u8], Option<&[u8]>) {
    match line.iter().position(|&b| b == b' ') {
        Some(i) => (&line[..i], Some(&line[i + 1..])),
        None => (line, None),
    }
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n');
    let capacity = match lines.next().and_then(parse_leading_int) {
        Some(c) if c >= 1 => usize::try_from(c).unwrap_or(usize::MAX),
        _ => return Ok(()),
    };

    let mut cache: LruCache<Box<[u8]>, Box<[u8]>> = LruCache::new(capacity);

    for line in lines {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            continue;
        }
        match split_command(line) {
            (b"SET", Some(args)) => {
                if let Some(i) = args.iter().position(|&b| b == b' ') {
                    cache.insert(args[..i].into(), args[i + 1..].into());
                }
            }
            (b"GET", Some(key)) => {
                let value = cache.get(key).map_or(&b"NULL"[..], |v| &v[..]);
                out.write_all(value)?;
                out.write_all(b"\n")?;
            }
            (b"DEL", Some(key)) => {
                let removed = cache.remove(key).is_some();
                out.write_all(if removed { b"1\n" } else { b"0\n" })?;
            }
            (b"SIZE", _) => writeln!(out, "{}", cache.len())?,
            // Unknown or malformed commands are ignored.
            _ => {}
        }
    }
    Ok(())
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    run(&input, &mut out)?;
    out.flush()
}
