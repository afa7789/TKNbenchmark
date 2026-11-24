# range — prove a private value is in range and above a public threshold

Write a circuit with:

- a **private** input `age`;
- a **public** input `threshold`.

The circuit must be satisfiable exactly when `0 ≤ threshold ≤ 255`, `0 ≤ age ≤ 255` and
`age ≥ threshold` (all as integers). Any other input, including values of 256 or more and huge field
elements, must make it unsatisfiable.

`build.sh` compiles the circuit. `bash prove.sh input.json` reads a JSON object such as
`{"age": "25", "threshold": "18"}` (decimal strings) and exits 0 if the circuit is satisfied (a
witness can be generated, or the program executes without a failed assertion), non-zero otherwise.

The tests run `prove.sh` on accepted and rejected inputs. Constraints must enforce the rules; checks
done only outside the circuit (for example in `prove.sh`) do not count.
