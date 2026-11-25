# Sources

- https://ocaml.org/changelog/2026-06-19-ocaml-550: the OCaml 5.5.0 changes. Used for modular explicits, `let type`, polymorphic parameters, the new String/Option/List/Int/Hashtbl functions, `Lazy.Mutexed`, and the breaking changes (`let rec (module ...)`, abstract types).
- https://ocaml.org/releases/5.4.0: the 5.4 features (labelled tuples, `iarray`, atomic record fields, the `Pair`/`Pqueue`/`Repr`/`Iarray`/`Char.Ascii` modules) and the breaks (`List.take`/`drop` on negative n, `sort_uniq`).
- https://ocaml.org/releases/5.3.0: the 5.3 changes. Used for the deep effect handler syntax, `List.take`/`drop`, the `Dynarray` additions, and `Domain.self_index`.
- https://ocaml.org/manual/5.5/effects.html: the syntax for declaring, performing and handling effects (`effect E, k ->`), `continue`/`discontinue`, and the rule that a continuation is resumed once.
- https://ocaml.org/docs/guidelines: the official programming guidelines. Used for exhaustive matches without `_` on own variants, avoiding `try ... with _`, parenthesizing nested matches, avoiding `hd`/`tl`, `.mli` per module, and limiting `open`.
- https://ocaml.org/docs/your-first-program: the `dune init proj` layout (bin/lib/test), `dune exec`, watch mode, and adding libraries and ppx to dune files.
- https://ocaml.org/docs/publishing-packages-w-dune: publishing with `dune-release bistro` and the `CHANGES.md` format.
- https://raw.githubusercontent.com/ocaml/dune/main/AGENTS.md: dune's own agent rules. Used for `dune build @check @fmt @runtest`, cram tests as the main mechanism, `dune promote`, not disabling warnings, `.mli` per `.ml`, and avoiding `assert false`.
- https://tangled.org/gazagnaire.org/prune/blob/main/docs/GUIDELINES.md: published OCaml project guidelines. Used for `.mli`-first design, abstract types, `result` for operational errors and exceptions only for bugs, `` `Msg `` errors, and cram/alcotest layout.
- https://codex.danielvaughan.com/2026/05/23/codex-cli-ocaml-development-mcp-merlin-dune-type-driven-agent-workflows/: the mistakes agents commonly make in OCaml (4.x idioms, wildcard arms, mixing Base and Stdlib), plus `dune build @check` as the compiler oracle and `dune fmt --check`.
- https://agent-skills.md/skills/plurigrid/asi/ocaml: a community OCaml skill. It confirms that the opam + dune + merlin + ocamlformat toolchain is the shared baseline.
- https://ocaml.org/changelog/2026-06-30-dune3240 and https://ocaml.org/backstage/2025-05-19-portable-lock-directories-for-dune-package-management: the current state of dune package management (`dune pkg lock`).
- Local install (/opt/homebrew/lib/ocaml/*.mli and list.ml/stdlib.ml, `dune --help`, `opam --help`, `ocamlopt -config`): checked every signature, label, command and flag. Scratch builds compiled and ran every code snippet, reproduced the error messages quoted in the skill, tested cram/promote, the dev vs release warning behaviour, the right-to-left evaluation order, and the tail-mod-cons in List and `@`.
