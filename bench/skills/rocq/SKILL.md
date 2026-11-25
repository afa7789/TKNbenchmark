---
name: rocq
description: "Version-correct, idiomatic Rocq for the installed toolchain (The Rocq Prover, version 9.3.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Rocq code."
---

# Rocq 9.3 (formerly Coq)

Checked against Rocq 9.3.0 and dune 3.25. Fix deprecation warnings; don't silence them.

## Toolchain
- There is one CLI, `rocq`. Use `rocq c` (compile), `rocq repl`, `rocq dep`, `rocq makefile`, `rocq doc` and `rocq check` (the kernel re-checker). The `coqc`/`coq_makefile` shims still work; write `rocq` in new scripts.
- Libraries: `Corelib` ships with Rocq, and its auto-loaded Prelude gives `nat`, `bool`, `list`, `option`, `Nat.*`, `length` and `++`. `Stdlib` is a separate package (`rocq-stdlib`, pulled in by `opam install rocq-prover`). `Ltac2` is the third.
- Load-path flags: `rocq c -Q dir Name f.v` requires qualified imports (`From Name Require Import A.`). `-R dir Name` also lets bare `Require Import A.` resolve.
- Flags: `-w +deprecated`, `-vos` (skips opaque proofs, for fast iteration), `-time`.

## Imports (the #1 source of breakage)
```coq
From Stdlib Require Import List Arith Lia ZArith Bool String.
Import ListNotations.        (* [1;2] syntax: Require is not enough *)
```
- `From Coq`, `Coq.Lists.List` and bare `Require Import List.` all emit deprecation warnings. Always write `From Stdlib`.
- `omega` and `Omega` are gone; use `lia` (`From Stdlib Require Import Lia`). For nonlinear goals use `nia`; for ring equalities use `ring` (after Arith/ZArith).
- Stdlib modules no longer re-export ZArith/Lia transitively. Require what you use.
- The Prelude has no `map` and no `/` on nat. `List.map` is "not found" without `List`, and `x / 2` gives `Unknown interpretation for notation "_ / _"` without `Arith`.
- ssreflect lives in Corelib: `From Corelib Require Import ssreflect ssrbool ssrfun.`
- Extraction: `From Stdlib Require Import Extraction.` (plus `ExtrOcamlBasic`, `ExtrOcamlNatInt`, ...).

## Renamed or deprecated (agents get these wrong)
| Old | Use in 9.3 |
|---|---|
| `Notation foo := t.` (abbreviation) | `Abbreviation foo := t.` (9.2) |
| `Hint Resolve l.` | `#[export] Hint Resolve l : core.` |
| `Hint Resolve l : mydb.` (new db) | first `Create HintDb mydb.` (9.2) |
| `Hint Rewrite l : rdb.` (new db) | first `Create Rewrite HintDb rdb.` |
| `app_length`, `map_length`, `rev_length`, `seq_length`, `firstn_length`, `combine_length` | `length_app`, `length_map`, `length_rev`, `length_seq`, `length_firstn`, `length_combine` |
| `if o then a else b` where `o` is not a bool | `if o is Some _ then a else b` (constructor args required) |
| ssreflect `rewrite` | `rw` (9.3; `rewrite` warns `rewrite-rw`) |
| `Variable x : T.` outside a section | now an error. Use `Context`/`Variable` inside `Section`, or `Parameter`/`Axiom` |
| `Zeq_bool`, `Zmod` | `Z.eqb`, `Z.modulo` (`mod`) |
| implicit `Notation ... : my_scope` | `Declare Scope my_scope.` first |

- `is` and `of` are keywords in 9.3 (`Definition is := ...` is a syntax error).
- New 9.3 syntax:
  - Record update: `{| p with px := 5 |}`.
  - Pattern test: `if n is S k then k else 0`.
  - Anonymous constructor args: `Inductive t := C of nat & bool.`

## Project layout and build
**rocq makefile** (the most common build, and what opam files call):
```
_RocqProject:            # _CoqProject is still read by some IDEs
  -R theories MyLib
  theories               # every .v below; or list files one by one
rocq makefile -f _RocqProject -o RocqMakefile --rocq-package rocq-mylib
make -f RocqMakefile -j        # also: install, html, validate, vos, clean
```
- Without `--rocq-package` (or `--no-rocq-package-warning`) you get a deprecation warning. It needs exactly one `-R`/`-Q`.
- Put make extensions in `RocqMakefile.local`. Pass compile flags with `-arg -w -arg +deprecated` in `_RocqProject`.

**dune** needs `(lang dune 3.24)` for `(using rocq 0.14)`. Lower dune lang versions reject 0.12 and up.
```
; dune-project
(lang dune 3.24)
(using rocq 0.14)
(package (name rocq-mylib) (depends rocq-core rocq-stdlib))
; theories/dune
(include_subdirs qualified)
(rocq.theory (name MyLib) (package rocq-mylib) (theories Stdlib))
```
- Stdlib is never implicit in dune; without `(theories Stdlib)` you get `Cannot find a physical path bound to logical path ... Stdlib`.
- `(package ...)` needs the package declared in dune-project or a `rocq-mylib.opam` file.
- The old `(stdlib no)` field is now `(no_corelib)`.
- CI: use `coq-community/docker-coq-action@v1` with `custom_image: rocq/rocq-prover:9.3`.

## Release and audit checklist
- `grep -rn "Admitted\|admit\|Axiom" theories/`. `Admitted.` compiles silently and turns the lemma into an axiom.
- `Print Assumptions thm.` must say `Closed under the global context` or list only intended axioms (`functional_extensionality_dep`, `classic`, ...).
- `rocq check -silent -o -Q theories MyLib MyLib.Main` re-checks the `.vo` files and lists every axiom.

## Proof idioms that are correct and fast
```coq
Lemma sum_app (l1 l2 : list nat) : sum (l1 ++ l2) = sum l1 + sum l2.
Proof.
  induction l1 as [| x xs IH]; simpl.
  - reflexivity.
  - rewrite IH. lia.
Qed.
```
- Always start with `Proof.` (otherwise you get `missing-proof-command`). Name hypotheses with `intros`/`as` patterns, and use bullets `-` `+` `*`.
- Annotate binders: `forall n, n = n` fails with `Cannot infer the implicit parameter A of eq`.
- Bool/Prop: `destruct (Nat.eqb_spec a b)` and `Nat.leb_spec` (`reflect`, from Arith). Also `Nat.eqb_eq`, `Nat.ltb_lt`, `Z.eqb_eq`, `andb_true_iff`.
- `lia` treats `/` and `mod` as opaque atoms.
  - On Z: `Z.to_euclidean_division_equations; lia` (or `Z.div_mod_to_equations`).
  - On nat: `pose proof (Nat.div_mod_eq x 2); pose proof (Nat.mod_upper_bound x 2); lia`.
- Decidable equality: `Scheme Equality for color.` gives `color_beq` and `color_eq_dec` (or prove it with `decide equality. Defined.`).
- `Qed` is opaque to `Compute`. Use `Defined` only when the term must compute (decision procedures, well-founded recursion).
- `Opaque f` does not stop `reflexivity` or kernel conversion. Use `Arguments f : simpl never.` to keep `simpl` from unfolding.
- Unary `nat` is slow: computing `fact 9` takes about 2 s. Use `N`/`Z` (binary) for real arithmetic.
- When `Qed` is slow, prefer `lazy`/`cbn` on the goal over `simpl in H`. Diagnose with `Time Qed.` and `Profile Qed.`.
- Search before proving: `Search (_ + 0 = _).`, `Search "rev" "app".`, `Locate "++".`
- Give hints and instances an explicit locality: `#[export]` or `#[local]`.

## Non-structural recursion
```coq
From Stdlib Require Import Program Lia.
Program Fixpoint f (n : nat) {measure n} : nat :=
  match n with 0 => 0 | S m => f m end.     (* obligations auto-solved here *)
Program Definition p (n : nat) (H : n > 0) : {m | S m = n} :=
  match n with 0 => _ | S k => k end.
Next Obligation. lia. Qed.
```
- A custom obligation tactic replaces the default, so chain onto it: `#[local] Obligation Tactic := program_simpl; try lia.`
- Unsolved obligations fail at end of file.
- Alternative: `From Stdlib Require Import Recdef.` then `Function f (n : nat) {measure (fun x => x) n} : nat := ...` followed by `Proof. intros; lia. Defined.`

## Error to fix
| Error | Fix |
|---|---|
| `Cannot guess decreasing argument of fix` / `Recursive call to f has principal argument equal to ...` | add `{struct x}`, or use `{measure}`, `Function` or fuel |
| `Non strictly positive occurrence of "T"` | redesign the type: no `T` left of an arrow in constructor args |
| `Attempt to save an incomplete proof` | goals remain; check bullets and `Show.` |
| `Unable to locate library X with prefix Stdlib` | wrong module name (e.g. `Omega`), or a missing dune `(theories Stdlib)` |
| `Unable to locate library A` | used `-Q` with a bare `Require`; write `From Name Require Import A.` |
| `The reference X was not found` | missing `Require`/`Import` or renamed lemma; `Search`/`Locate` |
| `Syntax error: [lconstr] expected` on `[1;2]` | add `Import ListNotations.` |
| `Tactic failure: Cannot find witness` (lia) | goal is nonlinear or uses div/mod: add facts, or use `nia` |
| `No obligations remaining` | remove the `Next Obligation` (it was auto-solved) |
