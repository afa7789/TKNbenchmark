# Sources

## Official documentation (Dafny 4.11.0)
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/RELEASE_NOTES.md: 4.11 changes (new Std libraries, FileIO UTF-8 API, `FromUTF8Checked` now returns `Result`, `SetToSeq` removed, real-literal syntax, trait method redeclaration) and breaking changes in 4.4–4.10 (`--allow-warnings`, `--allow-deprecation`, `{:rlimit}`→`{:resource_limit}`, `--boogie-filter`→`--filter-symbol`, hide/reveal, opaque blocks, @-attributes, `--isolate-assertions`).
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/docs/DafnyRef/UserGuide.md: CLI commands (verify/run/build/test/translate/format/audit), exit codes, `dafny run` argument rules, `dfyconfig.toml` project file format, `.doo` library files, verification debugging.
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/docs/DafnyRef/Attributes.md: list of `@`-attribute names (`@Test`, `@IsolateAssertions`, `@ResourceLimit`, `@Axiom`, `@VerifyOnly`, `@TailRecursion`, ...).
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/docs/DafnyRef/Modules.md: import/opened/alias rules for modules.
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/docs/VerificationOptimization/VerificationOptimization.md: brittleness guidance (isolate assertions, opaque definitions, keep solver context small, resource counts over time).
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/Source/DafnyStandardLibraries/README.md: `--standard-libraries` usage, list of Std modules, incompatibility with `--unicode-char:false`, translation caveats.
- https://raw.githubusercontent.com/dafny-lang/dafny/v4.11.0/docs/HowToFAQ/FAQStandardLibrary.md: pointer to the standard libraries FAQ.
- https://dafny.org/blog/2023/12/20/standard-libraries: Std library design (partial vs. complete function variants, opt-in flag).
- https://dafny.org/blog/2023/12/01/avoiding-verification-brittleness/: why proofs break and how to stabilize them (resource limits, opacity).
- Installed toolchain `/opt/homebrew/Cellar/dafny/4.11.0/libexec/DafnyStandardLibraries*.doo` (unzipped `program` source): exact Std signatures (Wrappers, Collections.Seq/Map, Strings, Math, Arithmetic lemmas, FileIO, JSON.API, Unicode), checked locally rather than taken from the web.

## Style guide
- https://dafny.org/dafny/StyleGuide/Style-Guide (raw: docs/StyleGuide/Style-Guide.md at v4.11.0): naming (camelCase vars, PascalCase decls), 2-space indent, brace placement, import style, explicit base cases in inductive lemmas, no redundant parentheses.

## Community agent rules / skills
- https://github.com/midspiral/LemmaScript/blob/HEAD/AGENTS.md: iterate with `--filter-symbol`, use `--isolate-assertions`, never use `assume` to paste over proof failures, empty lemma body means proved, and use `Std.Arithmetic` lemmas for flaky nonlinear goals.
- https://github.com/midspiral/lemmafit/blob/HEAD/skills/lemmafit-dafny/SKILL.md: parenthesize nested `match` expressions, and temporary `assume {:axiom}` only while scaffolding.
- https://github.com/metareflection/dafny-replay/blob/HEAD/.claude/CLAUDE.md: spec-first workflow; verify with `dafny verify`, then `dafny translate js`, and never hand-edit generated code.
- https://github.com/elizaOS/eliza/blob/HEAD/.agents/skills/prove/SKILL.md: `Std.Collections.Seq.Filter` is opaque, lambdas only match when they are the same term, and prefer resource limits to time limits.
- https://github.com/sunblaze-ucb/vero/blob/HEAD/.claude/skills/vero-dafny-pitfalls/SKILL.md: ghost vs. compiled, and function vs. method vs. lemma distinctions that agents confuse.

## Build / CI practice
- https://github.com/dafny-lang/setup-dafny-action: the standard GitHub Action (`uses: dafny-lang/setup-dafny-action@v1`, `dafny-version` input).
- https://dafny.org/dafny/Installation: install channels (release zips, Homebrew, `dotnet tool install Dafny --version`).
