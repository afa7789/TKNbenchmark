use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut input = Vec::new();
    let result = io::stdin()
        .lock()
        .read_to_end(&mut input)
        .map_err(lru::Error::from)
        .and_then(|_| {
            let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
            lru::run(&input, &mut out)?;
            out.flush()?;
            Ok(())
        });
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("app: {e}");
            ExitCode::FAILURE
        }
    }
}
