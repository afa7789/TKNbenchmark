# TKNbenchmark

How much does a coding agent spend, in tokens and dollars, to solve the **same tasks** in
**C, C++, C#, Rust, Go, Zig, Odin, Nim, Swift, Java, Kotlin, Clojure, OCaml, Haskell, JavaScript, TypeScript, Python
and Assembly (AArch64)**?
And on the front end, **React, Vue or Svelte**? Plus four specialised tracks: scientific computing
(**Octave, Julia, R**), theorem proving (**Lean 4, Rocq, Dafny**), smart contracts (**Solidity, Vyper**) and
zero-knowledge circuits (**Circom, Noir**).

Results: **https://afa7789.github.io/TKNbenchmark/** · Paper: [`paper.pdf`](https://afa7789.github.io/TKNbenchmark/paper.pdf) ([LaTeX source](paper/paper.tex))

## How it works

Inspired by [DeepSWE](https://deepswe.datacurve.ai/) (one agent per task, hidden tests) and by the series
["The Tokenomics of Web Development"](https://hackernoon.com/we-measured-the-llm-token-cost-of-5-languages-typescript-costs-31percent-more-than-javascript)
(tokens per language).

1. **Write** (`bench/run.mjs`): one headless `claude -p` per case (language × task × repetition), model
   `claude-opus-5-5`, effort `high`, only `Bash/Read/Edit/Write`, no web/MCP/plugins/CLAUDE.md, in an empty
   directory outside the repo. The prompt is identical for every language. The agent gets `SPEC.md`,
   examples (`cases.json`) and the checker (`check.mjs`).
2. **Verify, once, live** (`bench/verify.mjs`, `bench/verify-front.mjs`): back ends get a cold build of a
   clean copy with isolated caches (time and disk, including `target/`, `.zig-cache`, `GOCACHE`…), then the
   **hidden** suite. Front ends get a Vite build and checks in headless Chromium with mocked network.
3. **Repair** (`bench/repair.mjs`): each failure gets a fresh agent with the failure report, up to 3
   attempts; we measure cost and time to green.
4. **Performance** (`bench/perf.mjs`): passing binaries on large inputs, median of 5 runs plus peak memory;
   kvhttp in req/s with 64 clients. `bench/devloop.mjs` measures Rust's full dev loop (debug + release +
   test builds).
5. **Code tokens** (`bench/count.mjs`): final code counted with Opus 5.5's tokenizer (input-token delta of a
   `claude -p` with and without the code) and with cl100k, to compare with the article.
6. **Aggregate** (`bench/aggregate.mjs`) → `public/data/results.json` → static page in `public/`, and
   `paper/build.mjs` → `paper/data.tex` → `public/paper.pdf`.

| Task | What it exercises |
|---|---|
| [`wordfreq`](bench/tasks/wordfreq/SPEC.md) | bytes, hash maps, sorting; 30–50 MB inputs |
| [`lru`](bench/tasks/lru/SPEC.md) | O(1) linked structure; 1 million commands |
| [`calc`](bench/tasks/calc/SPEC.md) | recursive-descent parser, int64 overflow |
| [`kvhttp`](bench/tasks/kvhttp/SPEC.md) | concurrent HTTP server; dependencies allowed |
| [`ui`](bench/tasks/ui/SPEC.md) | 6 components in React, Vue and Svelte |
| [`linreg`](bench/tasks/linreg/SPEC.md), [`linalg`](bench/tasks/linalg/SPEC.md) | track: scientific computing, numeric tolerance 1e-6 |
| [`lists`](bench/tasks/lists/SPEC.md), [`isort`](bench/tasks/isort/SPEC.md) | track: theorem proving, no escape hatches, statements unchanged |
| [`token`](bench/tasks/token/SPEC.md), [`vesting`](bench/tasks/vesting/SPEC.md) | track: smart contracts on a fresh anvil (reverts, events, exact time) |
| [`range`](bench/tasks/range/SPEC.md), [`sudoku`](bench/tasks/sudoku/SPEC.md) | track: zero-knowledge circuits, valid inputs provable and invalid ones not |
| [`shop`](bench/tasks/shop/SPEC.md) | mini app: parent/child, global store (agent's choice), derived state, form, effect with cleanup, context, slots |

Each back-end task has a JS reference implementation; `npm run selftest` proves the checker accepts it on
both the visible and the hidden suite. For front ends, `npm run selftest:front` does the same with the
reference components in `bench/front-ref/`, and `npm run selftest:tracks` checks every track's reference
solutions (and that the untouched proof templates fail).

## Reproduce

Needs Node 24+, each language's toolchain, a logged-in Claude Code, and `tectonic` for the paper.

```sh
npm ci
npm run selftest            # the verifier accepts the reference solutions
npm run bench -- --reps 3   # agents (--langs rust,zig --tasks lru to filter)
npm run verify              # round 3: cold build + hidden tests (one at a time)
npm run verify:front        # round 3: front end with Vite + Chromium (Playwright)
npm run repair              # round 4: fresh agent with the failure report, up to 3 attempts
npm run perf                # performance (idle machine)
npm run count               # code tokens
npm run aggregate           # public/data/results.json
npm run paper               # paper/data.tex + public/paper.pdf + paper/arxiv.tar.gz
npm run serve               # http://localhost:8080
```

`npm run check` (lint with complexity ≤ 10 + selftest + data validation) is the CI gate.

### Arm 2: with a language skill

The published run is the **no-rules** arm: the agent gets no CLAUDE.md, no skills and no Skill tool. The
skills arm repeats every round with one change: the workdir holds `.claude/skills/<lang>/SKILL.md` and the
agent gets the `Skill` tool (bundled skills off, so it sees only its language's skill).

1. **Write the skills** (`npm run skills`): one agent per language (same model and effort, web access)
   researches what practitioners use for the installed version, checks every API and command against the
   toolchain, and writes a body of at most 8 000 bytes. The prompt (`skillPrompt` in `bench/config.mjs`) is
   the same for every language and never mentions the benchmark; the harness adds the same front matter to
   every skill. Output: `bench/skills/<lang>/SKILL.md`, `SOURCES.md`, and cost in `bench/skills/meta.json`.
2. **Run the arm** with the baseline's Claude Code (`run.mjs` refuses any toolchain drift from
   `runs/toolchains.json`); front ends build with the baseline's pinned React, Vue, Svelte and Vite.

```sh
export TKN_ARM=skills TKN_CLAUDE=~/.local/share/claude/versions/2.1.331
npm run skills
npm run bench -- --reps 3 && npm run verify && npm run verify:front && npm run repair
npm run perf -- --paired && npm run count && npm run aggregate   # into runs-skills/; perf of both arms, interleaved
```

## Layout

```
bench/
  config.mjs          model, languages, tasks, prompts
  agent.mjs           one headless claude -p per case
  run.mjs             round 1–2: write
  skills.mjs          skills arm: one SKILL.md per language (bench/skills/<lang>/)
  transcript.mjs      stream-json transcript → metrics
  verify.mjs          round 3 (back end): isolated cold build + hidden suite
  verify-front.mjs    round 3 (front end): Vite + Chromium smoke checks
  repair.mjs          round 4: repair with the failure report
  perf.mjs            performance of passing binaries
  devloop.mjs         Rust debug + release + test target/ size
  count.mjs           code tokens (Opus 5.5 + cl100k)
  deps.mjs            dependencies read from build manifests
  aggregate.mjs       runs/ → public/data/results.json
  harness/check.mjs   black-box checker (copied into every case)
  tasks/<task>/       SPEC.md, reference.mjs, cases.mjs (visible + hidden)
runs/<lang>/<task>/r<n>/   solution/, agent.json, verify.json, perf.json, tokens.json, repair.json
runs-skills/…               the same, for the skills arm
paper/                paper.tex, build.mjs (→ data.tex), arxiv.mjs (→ arxiv.tar.gz)
public/               the page (GitHub Pages) and paper.pdf
```

## Sponsor the next round

Every run here was paid for out of pocket. Sponsorship buys more repetitions, other models and agents,
bigger multi-hour tasks, clean machines (a Linux runner and a Mac with Xcode, which removes the Swift and
C# toolchain confound) and more languages and stacks. Email **abeilice@ufmg.br** with what you would like
measured and your budget; sponsors are acknowledged on the results page.

Or donate directly:

- BTC: `bc1qqjykl9nym5qn9u2dpqt0vfz8cgl4pt3n8mkngq`
- ETH: `0xa2FB6CA627659644EFeBe3A83361e22e8B34921C`
- XMR: `42Nv3KCbqexE78fZMeMrjRHMDME62s5Jya71Pz12e79HUP6Wwbr37uG9ukRWrtvTg2WkikNk1NCz4RcU3dDcafUhLtdTdfY`

## Contributing

Suggestions, corrections and changes to the method are welcome: new tasks, new languages, a better
harness, or a re-run on another model or machine. See [CONTRIBUTING.md](CONTRIBUTING.md), open an issue
or a pull request, or email **abeilice@ufmg.br**.

## License

[MIT](LICENSE), except the Faktum typeface in `public/fonts/`, which belongs to its foundry (see [NOTICE](NOTICE)).
