# Sources

## Official documentation and release notes
- https://rocq-prover.org/doc/V9.3.0/refman/changes.html — Changelogs for 9.3, 9.2, 9.1, 9.0 and 8.20:
  - ssreflect `rewrite` → `rw`; `if … is` syntax; `is`/`of` keywords; record `with` syntax.
  - `Abbreviation`; `Create HintDb` / `Create Rewrite HintDb` requirements; `intuition` change.
  - `-verbose` removed; dune ≥ 3.21 for `rocq.theory`; 8.20 `length_*` renames; `Variable` outside a section is an error.
- https://rocq-prover.org/releases/9.0.0 — 9.0 completes the Coq→Rocq rename and introduces the single `rocq` CLI.
- https://rocq-prover.org/doc/V9.3.0/refman/practical-tools/utilities.html — `_RocqProject` format, the `rocq makefile` workflow, `--rocq-package` / `--legacy-support`, the findlib META `rocqpath` field, and Dune and `rocq dep` notes.
- https://rocq-prover.org/doc/master/refman-stdlib/changes.html — Stdlib changelog:
  - the `From Stdlib` prefix is mandatory; no transitive ZArith/Lia;
  - `Zeq_bool` deprecated; `Zmod` removed;
  - new Zdiv lemmas, the 9.1 file splits, and the 9.2 notation levels.
- https://dune.readthedocs.io/en/latest/rocq.html — Dune Rocq language:
  - `(using rocq 0.14)` and the `rocq.theory` fields;
  - `(theories Stdlib)` is required; `(stdlib …)` became `(no_corelib)`;
  - `include_subdirs qualified`, `rocq.extraction`, `dune rocq top`.
- https://rocq-prover.org/docs/using-opam — the opam repo `rocq-released`, `opam install rocq-prover`, and pinning `rocq-core`.

## Style guides
- https://github.com/coq/coq/wiki/CoqStyle — `Proof.` on its own line; indent per subgoal; name hypotheses with `as`/`intros`; follow stdlib lemma naming.
- https://github.com/UniMath/UniMath/wiki/Style-Guide — Prefer bullets `-` `+` `*` over braces.
- https://sources.debian.org/src/coq-iris/4.3.0-1/docs/style_guide.md — Iris/stdpp conventions:
  - explicit `Local`/`Global` on Hint/Instance/Arguments;
  - `Context` over `Variable`; `Require` at the top;
  - layout of long statements.
- https://prl.khoury.northeastern.edu/blog/2017/02/21/bullets-are-good-for-your-coq-proofs — Why bullets make proofs robust to change.

## Agent skills and rules published by Rocq users
- https://claudskills.com/skills/coqtail-mcp/SKILL.md — Agreed agent practices:
  - search the library (`Search`/`Check`/`Print`) before proving;
  - never change theorem statements and never add axioms silently;
  - grep for `Admitted`; check `Print Assumptions` against the standard axioms.
- https://skillsmp.com/creators/ejgallego/lean-beam/skills-rocq-beam — The rocq-beam agent skill, which describes a goal-driven, incremental checking workflow. Its raw file returned 404, so only the listing was used.
- https://clawhub.ai/skills/openmath-rocq-theorem — A Rocq proving skill that also follows the search-first, verify-assumptions pattern.

## Troubleshooting, performance and CI
- https://github.com/coq/coq/wiki/Troubleshooting — Slow-`Qed` diagnosis (`Profile Qed`, `Time Qed`); `simpl`/`cbn` in hypotheses as the usual cause; `abstract`; `{struct}` for guard slowness.
- https://unimath.github.io/UniMath/documentation/guides/faq/Slow-proof.html — More advice on slow proofs and reduction.
- https://github.com/rocq-community/docker-coq-action (redirects from coq-community) — GitHub Action `@v1` with `custom_image: rocq/rocq-prover:9.x` for Rocq ≥ 9.0.
- https://hub.docker.com/r/rocq/rocq-prover — Official Docker images; confirmed the 9.3 tags exist.
- https://github.com/coq-community/templates — Community project templates (meta.yml → opam/CI files).

## Local verification (Rocq 9.3.0, dune 3.25.0, macOS arm64)
Every API name, import path, command, flag and error message in SKILL.md was checked by compiling snippets with `rocq c`, `rocq makefile` + `make`, `dune build` and `rocq check` in a scratch directory, which has since been deleted. Two findings:
- `lia` does not handle nat or Z `/`/`mod` directly.
- `(using rocq 0.14)` requires `(lang dune 3.24)`.
