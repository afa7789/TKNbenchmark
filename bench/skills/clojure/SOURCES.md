# Sources

- https://clojure.org/releases/devchangelog: the 1.12.0 to 1.12.7 patch changes, and the list of 1.13 alpha-only features (req!, merge-deep, destructuring directives) to avoid.
- https://clojure.org/news/2024/09/05/clojure-1-12-0: 1.12 features (qualified methods, param-tags, array class syntax, FI conversion, stream fns, partitionv/splitv-at, add-lib, clojure.java.process).
- https://clojure.org/news/2025/06/02/clojure-1-12-1: confirmed the patch-release cadence and the qualified-symbol revert.
- https://clojure.org/reference/java_interop: type hints, reflection warnings, primitive arg limits, field access with `.-`, and functional-interface hinting.
- https://clojure.org/reference/deps_edn: deps.edn keys, alias keys, and git/mvn/local coordinates.
- https://clojure.org/reference/clojure_cli: -M/-X/-T/-P/-Stree flags, EDN quoting rules for -X args, and the -X:deps tools.
- https://clojure.org/guides/tools_build: the build.clj uber/jar pattern and the :build alias shape.
- https://github.com/clojure/tools.build: current tag v0.10.14 / sha 1176afd (also checked with git ls-remote).
- https://github.com/cognitect-labs/test-runner: the :test alias (v0.5.1 / dfb30dd) and the -X/-M options (-v, -n, -i, :dirs).
- https://www.clojure.org/guides/repl/annex_troubleshooting: the common "Could not locate", "No such namespace", and ClassNotFoundException errors and their fixes.
- https://guide.clojure.style/: the community style guide (ns form ordering, naming, idioms, ex-info, docstrings, clojure.math over Math/).
- https://github.com/seancorfield/deps-new/blob/develop/README.md: how experienced devs scaffold projects (app/lib templates, `clojure -T:build ci`).
- https://awesome-copilot.github.com/instruction/clojure/: published agent rules (REPL-first, docstring placement, don't shadow core names, reload namespaces, rich comment forms).
- https://github.com/bhauman/clojure-mcp-light: agents' delimiter "death loop" problem, and advice to repair or rewrite whole forms and to use :reload.
- https://github.com/bhauman/clojure-mcp: the REPL-connected structural editing approach for agents.
- https://skills.sh/metabase/metabase/clojure-write: Metabase's Clojure agent skill (prefer REPL eval tools and structural edits over shell).
- https://codex.danielvaughan.com/2026/05/23/codex-cli-clojure-development-teams-clojuremcp-repl-driven-agent-workflows/: an AGENTS.md template (pin deps, clj-kondo after edits, tests mirror src).
- Installed toolchain (Clojure CLI 1.12.7.1681, Clojure 1.12.7, OpenJDK 27): every snippet, command, alias and error message in SKILL.md was run in a scratch project.
