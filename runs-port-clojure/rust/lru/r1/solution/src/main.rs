//! LRU cache simulator: reads a capacity and a stream of commands from stdin,
//! writes command results to stdout. See SPEC.md.

mod cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

type Cache = LruCache<Box<[u8]>, Box<[u8]>>;

/// Splits input into lines terminated by `\n`, `\r`, or `\r\n`, skipping empty lines.
fn lines(input: &[u8]) -> impl Iterator<Item = &[u8]> {
    input
        .split(|&b| b == b'\n' || b == b'\r')
        .filter(|line| !line.is_empty())
}

/// Parses the capacity line, tolerating surrounding whitespace.
fn parse_capacity(line: &[u8]) -> Option<usize> {
    let text = std::str::from_utf8(line.trim_ascii()).ok()?;
    let n: i64 = text.parse().ok()?;
    Some(usize::try_from(n).unwrap_or(0))
}

/// Runs one command line against the cache, writing any output.
/// Unknown or malformed commands are ignored.
fn execute(cache: &mut Cache, out: &mut impl Write, line: &[u8]) -> io::Result<()> {
    let (cmd, rest) = match line.iter().position(|&b| b == b' ') {
        Some(sp) => (&line[..sp], &line[sp + 1..]),
        None => (line, line),
    };
    match cmd {
        b"SET" => {
            if let Some(sp) = rest.iter().position(|&b| b == b' ') {
                let (key, value) = (&rest[..sp], &rest[sp + 1..]);
                cache.put(key.into(), value.into());
            }
        }
        b"GET" => match cache.get(rest) {
            Some(value) => {
                out.write_all(value)?;
                out.write_all(b"\n")?;
            }
            None => out.write_all(b"NULL\n")?,
        },
        b"DEL" => {
            let reply: &[u8] = if cache.remove(rest).is_some() { b"1\n" } else { b"0\n" };
            out.write_all(reply)?;
        }
        b"SIZE" => writeln!(out, "{}", cache.len())?,
        _ => {}
    }
    Ok(())
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = lines(input);
    let Some(capacity) = lines.next().and_then(parse_capacity) else {
        return Ok(());
    };
    let mut cache = Cache::new(capacity);
    for line in lines {
        execute(&mut cache, out, line)?;
    }
    out.flush()
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("error reading stdin: {err}");
        return ExitCode::FAILURE;
    }
    let mut out = BufWriter::with_capacity(1 << 20, io::stdout().lock());
    match run(&input, &mut out) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("error writing stdout: {err}");
            ExitCode::FAILURE
        }
    }
}
