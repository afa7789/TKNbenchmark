//! `wordfreq`: print the 10 most frequent words read from standard input.

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP: usize = 10;

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = wordfreq::count_words(&mut input);
    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in wordfreq::top_n(&counts, TOP) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("wordfreq: {err}");
            ExitCode::FAILURE
        }
    }
}
