# Sources

## Web
- https://nim-lang.org/blog/2026/10/28/nim-240.html — Nim 2.4.0 announcement: sum types, `--mm:yrc`, `--strings:sso`, `--ic:on`, `{.cyclic.}` imports, raw string API, `addr s[i]` deprecation.
- https://raw.githubusercontent.com/nim-lang/Nim/v2.4.2/changelog.md — changelog at the v2.4.2 tag: bare `except:` vs Defect, `getOrDefault(def=)`, `setLenUninit`, `std/files`/`std/dirs` additions, `multiReplace` charset form, `std/nre2`, `re`/`nre`/`parsesql` deprecations. Some entries there (e.g. `lent` array `items`, `nimPreviewDuplicateModuleError`) did not behave as described on 2.4.2, so I left them out.
- https://raw.githubusercontent.com/nim-lang/Nim/v2.4.2/changelogs/changelog_2_2_0.md — 2.2 breaking changes: strict `delete`, non-var destructors, no partial generic instantiation, const scoping.
- https://nim-lang.org/blog/2025/10/31/nim-226.html and https://nim-lang.org/blog/2026/02/23/nim-228.html (search results) — 2.2.x patch-release timeline leading to 2.4.
- https://nim-lang.org/docs/nep1.html — official style guide (NEP1): naming, `std/` imports, `Error`/`Defect` suffixes, `result` over `return`, `let` over `var`, getter/setter naming.
- https://status-im.github.io/nim-style-guide/ — Status Nim style guide intro: safe defaults, compile-time strictness, target Nim 2.2.
- https://status-im.github.io/nim-style-guide/errors.exceptions.html — `{.push raises: [].}` at module top, explicit `raises` on public procs, `CatchableError` vs `Defect`, don't catch Defect outside tests.
- https://status-im.github.io/nim-style-guide/language.objconstr.html — build objects with `T(field: v)`, `init`/`new` constructor convention.
- https://nim-lang.github.io/nimble/create-packages.html — package layout (`src/`, `tests/t*.nim`, `tests/config.nims`), `.nimble` fields, `nimble init`, `nimble test`, tasks.
- https://raw.githubusercontent.com/nim-lang/nimony/master/AGENTS.md — the Nim core team's own agent guidelines: explicit state objects, flat procs over closures, strict/structured control flow.
- https://raw.githubusercontent.com/nim-lang/langserver/master/SKILL.md — official langserver MCP skill: `nim check`-style diagnostics are the first thing to run.
- https://hn.jakechampion.name/reader/https://gist.github.com/planetis-m/f28c1ce360f4a42d37ca0f1702d8e305 — community AGENTS.md generator for Nim: `t`-prefixed tests in `tests/`, `nimble lock`, `atlas use`, `distinct`/`range` types.
- https://skills.sh/alphaonedev/openclaw-graph/coding-nim — community Nim skill: run `nim check` before full builds, ARC/ORC. Its outdated `--gc:` flags are not used here (the flag is now `--mm:`).
- https://www.skills.sh/g1joshi/agent-skills/nim — community Nim skill: high-level 2.x overview only. It confirmed there is no shared, detailed community skill.

## Installed toolchain (verified locally, Nim 2.4.2, nimble 0.26.2)
- /opt/homebrew/Cellar/nim/2.4.2/nim/lib (system.nim, std/files.nim, std/dirs.nim, std/nre2.nim, std/sha1.nim, pure/md5.nim, pure/parsesql.nim, pure/concurrency/threadpool.nim, impure/re.nim) — signatures and deprecation pragmas.
- /opt/homebrew/Cellar/nim/2.4.2/nim/config/nim.cfg — what `-d:release`, `-d:danger`, `-d:lto` actually set.
- `nim --fullhelp`, `nimble --help` — flags and subcommands. Every snippet, command and error message in SKILL.md was compiled or run in a scratch project (also `nimble add results|regex|malebolgia`).
