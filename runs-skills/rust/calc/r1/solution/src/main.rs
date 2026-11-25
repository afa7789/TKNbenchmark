use std::io::{self, BufWriter, Read, Write};

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::new(io::stdout().lock());
    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|&b| b == b' ' || b == b'\t') {
            continue;
        }
        match calc::evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => writeln!(out, "error")?,
        }
    }
    out.flush()
}
