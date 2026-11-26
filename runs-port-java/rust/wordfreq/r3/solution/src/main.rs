//! Prints the ten most frequent ASCII words read from standard input.

mod counter;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use counter::WordCounter;

const TOP_N: usize = 10;

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    input.make_ascii_lowercase();

    let counter = WordCounter::from_text(&input);

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in counter.top(TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piping into `head`) is not an error worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wordfreq: {e}");
            ExitCode::FAILURE
        }
    }
}
