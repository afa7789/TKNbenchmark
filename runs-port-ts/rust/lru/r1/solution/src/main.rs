//! Simulates an LRU cache driven by commands on standard input (see SPEC.md).

mod lru;

use std::io::{self, BufWriter, Read, Write};
use std::num::NonZeroUsize;
use std::process::ExitCode;

use lru::LruCache;

type Cache = LruCache<Box<[u8]>, Box<[u8]>>;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut lines = input
        .split(|&b| b == b'\n')
        .map(|line| line.strip_suffix(b"\r").unwrap_or(line));
    // A trailing newline yields one final empty piece; empty lines are skipped anyway.

    let Some(header) = lines.next() else {
        return Ok(());
    };
    let capacity = parse_capacity(header).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "capacity must be a positive integer, got {:?}",
                String::from_utf8_lossy(header)
            ),
        )
    })?;

    let mut cache = Cache::new(capacity);
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    for line in lines.filter(|line| !line.is_empty()) {
        execute(&mut cache, line, &mut out)?;
    }
    out.flush()
}

/// Parses the leading decimal integer of the header line, tolerating
/// surrounding whitespace, a `+` sign and trailing garbage.
fn parse_capacity(header: &[u8]) -> Option<NonZeroUsize> {
    let text = header.trim_ascii();
    let text = text.strip_prefix(b"+").unwrap_or(text);
    let digits = text.iter().take_while(|b| b.is_ascii_digit()).count();
    std::str::from_utf8(&text[..digits]).ok()?.parse().ok()
}

/// Runs one non-empty command line, writing its output (if any).
fn execute(cache: &mut Cache, line: &[u8], out: &mut impl Write) -> io::Result<()> {
    let (command, rest) = match line.iter().position(|&b| b == b' ') {
        Some(i) => (&line[..i], &line[i + 1..]),
        // A bare command uses the whole line as its argument, like the original.
        None => (line, line),
    };

    match command {
        b"SET" => {
            if let Some(i) = rest.iter().position(|&b| b == b' ') {
                cache.set(rest[..i].into(), rest[i + 1..].into());
            }
        }
        b"GET" => {
            let value = cache.get(rest).map_or(&b"NULL"[..], |v| v);
            out.write_all(value)?;
            out.write_all(b"\n")?;
        }
        b"DEL" => {
            out.write_all(if cache.remove(rest) { b"1\n" } else { b"0\n" })?;
        }
        b"SIZE" => writeln!(out, "{}", cache.len())?,
        // Unknown commands are ignored; the spec defines no output for them.
        _ => {}
    }
    Ok(())
}
