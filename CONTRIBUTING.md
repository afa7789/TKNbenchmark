# Contributing

Suggestions, corrections and pull requests that improve the method are welcome. Questions or ideas that
don't fit an issue: **abeilice@ufmg.br**. To fund more runs, see "Sponsor the next round" in the
[README](README.md).

## Good contributions

- **A harness bug or an unfair check**: a verifier that rejects correct code, a spec that favours one
  language, a metric that miscounts. Open an issue with the run id (e.g. `ocaml-kvhttp-r1`) and what you
  expected. Two such bugs were found during the first run; see the paper's Limitations.
- **A new language or framework**, or **a new task**: see below.
- **A re-run** on another model, machine or OS. Include the model, effort, toolchain versions
  (`runs/toolchains.json`) and the machine.
- **Analysis**: better statistics, plots or write-up of the existing data.

## Ground rules

1. **Results are generated, never edited.** Don't hand-edit `runs/`, `public/data/` or `paper/data.tex`;
   change the code and regenerate (`npm run aggregate`, `npm run paper`).
2. **Same prompt for every language.** Language-specific lines (`note` in `bench/config.mjs`) only when a
   language cannot otherwise satisfy the contract (e.g. `./app` as a launcher script).
3. **Verifiers must prove themselves first.** A new task ships with a reference implementation that its
   own visible and hidden suites accept (`npm run selftest`, `npm run selftest:front`).
4. **Verify once, live.** Don't check agent output before the verify round; failures are part of the
   measurement. Classify each failure as harness or agent before keeping a repair result.
5. **The gate passes**: `npm run check` (ESLint with complexity ≤ 10, zero warnings; selftest; data
   validation) exits 0. One change per pull request.

## Adding a language

1. Add an entry to `LANGS` in `bench/config.mjs`: `label`, `name` (as shown to the agent), `version`
   (a command whose first line is the toolchain version) and, if needed, `note`.
2. In `bench/lib.mjs`, add its source extensions to `COUNTED_EXT` and its build-output directories to
   `SKIP_DIRS` (check real project layouts: `bin/` is output in .NET but source in dune).
3. In `bench/verify.mjs`, point its global caches into the sandbox in `sandboxEnv`.
4. In `bench/deps.mjs`, add a parser for its dependency manifest.
5. Run it: `npm run bench -- --langs <id> --reps 3`, then `verify`, `repair`, `perf`, `count`, `aggregate`.

## Adding a task

1. `bench/tasks/<id>/SPEC.md`: language-neutral, every rule testable.
2. `bench/tasks/<id>/reference.mjs`: a JS reference (stdin/stdout program or HTTP server).
3. `bench/tasks/<id>/cases.mjs`: `visible()` (given to the agent) and `hidden()` (a superset with edge
   cases and large inputs).
4. Register it in `TASKS` in `bench/config.mjs`; `npm run selftest` must pass.
