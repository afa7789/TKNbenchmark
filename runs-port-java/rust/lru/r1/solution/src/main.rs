//! Simulates an LRU cache: reads a capacity followed by cache commands from
//! standard input and writes command results to standard output, one per line.

mod cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

type Cache = LruCache<Box<[u8]>, Box<[u8]>>;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lru: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout().lock();
    let mut out = BufWriter::with_capacity(1 << 16, stdout);
    process(&input, &mut out)?;
    out.flush()
}

/// Executes every command in `input` against a cache sized by its first line.
fn process(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n').map(strip_carriage_return);
    // `split` yields a trailing empty slice after a final newline; blank
    // lines are ignored below, so it needs no special handling.
    let Some(header) = lines.next() else {
        return Ok(());
    };
    let capacity = parse_capacity(header)?;
    let mut cache = Cache::new(capacity);

    for line in lines {
        execute(&mut cache, line, out)?;
    }
    Ok(())
}

fn parse_capacity(header: &[u8]) -> io::Result<usize> {
    let invalid = || io::Error::new(io::ErrorKind::InvalidData, "invalid capacity");
    std::str::from_utf8(header)
        .map_err(|_| invalid())?
        .trim()
        .parse::<usize>()
        .ok()
        .filter(|&c| c > 0)
        .ok_or_else(invalid)
}

fn execute(cache: &mut Cache, line: &[u8], out: &mut impl Write) -> io::Result<()> {
    let (command, rest) = match line.iter().position(|&b| b == b' ') {
        Some(i) => (&line[..i], Some(&line[i + 1..])),
        None => (line, None),
    };

    match (command, rest) {
        (b"SET", Some(args)) => {
            if let Some(i) = args.iter().position(|&b| b == b' ') {
                cache.put(args[..i].into(), args[i + 1..].into());
            }
        }
        (b"GET", Some(key)) => {
            let value = cache.get(key).map_or(&b"NULL"[..], |v| &v[..]);
            write_line(out, value)?;
        }
        (b"DEL", Some(key)) => {
            let found = cache.remove(key).is_some();
            write_line(out, if found { b"1" } else { b"0" })?;
        }
        (b"SIZE", _) => writeln!(out, "{}", cache.len())?,
        // Blank, malformed or unrecognised lines are ignored.
        _ => {}
    }
    Ok(())
}

fn write_line(out: &mut impl Write, text: &[u8]) -> io::Result<()> {
    out.write_all(text)?;
    out.write_all(b"\n")
}

fn strip_carriage_return(line: &[u8]) -> &[u8] {
    line.strip_suffix(b"\r").unwrap_or(line)
}
